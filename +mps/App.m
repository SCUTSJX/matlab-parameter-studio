classdef App < handle
%APP The MATLAB Parameter Studio user interface.
%
%   app = mps.App() creates the window.  Most users should call the
%   MatlabParameterStudio launcher instead.

    properties
        UIFigure
        SourceFile = ''
        EntryFile = ''
        ProjectRoot = ''
        ProjectMode = false
        ProjectStamp = ''
        SourceStamp = struct()
        Results
        MaxVariableMB = 100
        MaxTotalMB = 512
        LazyWorkspaceMB = 32
        SaveFigFiles = false
        FigureResolution = 150
        NumWorkers = 0          % 0 = auto: conservative, capped by MaxWorkers
        MaxWorkers = 4
        BackgroundWorkers = 1
        SweepSeed = 0           % per-scenario base seed; [] disables seeding
        KeepParallelPool = false
        RunTimeoutSeconds = 0   % 0 = no timeout
    end

    properties (Dependent)
        Params
        SelectedParams
        SourceLines
        LastAnnotations
        AnnotationFile
    end

    properties (Access = private)
        FileLabel, StatusLabel
        FilterDrop, SearchField, FileFilterDrop, CountLabel
        Table, SourcePreview
        FigureDrop, FigureImage
        WorkspaceTable
        XDrop, YList, PlotStatus, UIAxes
        LogArea
        OpenButton, ProjectButton, RescanButton, RunButton, SaveButton, ReportButton
        FolderButton, ExportButton, CloseFiguresButton, HelpButton
        SelectAllButton, ResetButton, PlotButton, SavePlotButton, ExportCsvButton
        OpenReportInline
        AnnotationStatus, AnnotateTemplateButton, ImportAnnotationButton
        ClearAnnotationButton, LockButton, CompareButton, KeepFiguresCheck
        BackgroundCheck
        PresetDrop, PresetNameField, PresetSaveButton, PresetLoadButton
        PresetDeleteButton, SweepButton, BulkButton, ManualButton, EntryButton
        UndoButton, RedoButton
        IsFunctionFile = false
        Save
        TableCtl
        SourceCtl
        PresetCtl
        AnnotationCtl
        SweepCtl
        HistoryCtl
        Busy = false
        BackgroundMgr
    end

    methods
        function app = App(varargin)
            visible = 'on';
            for k = 1:2:numel(varargin)
                if k + 1 > numel(varargin), break; end
                if strcmpi(char(varargin{k}), 'Visible')
                    visible = char(varargin{k+1});
                end
            end
            try
                mps.cleanupShadowProjects(7);
            catch err
                mps.logWarning('清理旧影子目录', err);
            end
            app.createUI();
            app.SourceCtl = mps.SourceController(app, app.TableCtl);
            app.SourceCtl.RefreshFcn = @() app.refreshTableView();
            app.SourceCtl.StatusFcn = @(message) app.setStatusText(message);
            app.BackgroundMgr = mps.BackgroundRunManager(app.UIFigure);
            app.BackgroundMgr.ProgressFcn = ...
                @(message) app.backgroundProgress(message);
            app.BackgroundMgr.FinishedFcn = ...
                @(out, message) app.backgroundFinished(out, message);
            app.PresetCtl = mps.PresetController(app, app.PresetDrop, ...
                app.PresetNameField, app.PresetSaveButton, ...
                app.PresetLoadButton, app.PresetDeleteButton, ...
                app.StatusLabel);
            app.PresetCtl.UndoFcn = @() app.pushUndo();
            app.PresetCtl.RefreshFcn = @() app.refreshTable();
            app.AnnotationCtl = mps.AnnotationController(app, ...
                app.StatusLabel);
            app.AnnotationCtl.UndoFcn = @() app.pushUndo();
            app.AnnotationCtl.RefreshFcn = @() app.refreshTable();
            sweepCtx = struct();
            sweepCtx.App = app;
            sweepCtx.KeepFiguresCheck = app.KeepFiguresCheck;
            sweepCtx.LogArea = app.LogArea;
            sweepCtx.ReportButton = app.ReportButton;
            sweepCtx.FolderButton = app.FolderButton;
            sweepCtx.CloseFiguresButton = app.CloseFiguresButton;
            sweepCtx.CompareButton = app.CompareButton;
            sweepCtx.StatusLabel = app.StatusLabel;
            sweepCtx.SetBusyFcn = @(b) app.setBusy(b);
            sweepCtx.ConfirmFcn = @(label) ...
                app.confirmInteractiveCalls(label);
            app.SweepCtl = mps.SweepController(sweepCtx);
            app.HistoryCtl = mps.RunHistoryController(app, app.StatusLabel);
            app.HistoryCtl.UndoFcn = @() app.pushUndo();
            app.HistoryCtl.RefreshFcn = @() app.refreshTable();
            app.UIFigure.UserData = app;
            app.UIFigure.Visible = visible;
        end

        function delete(app)
            try
                app.cancelBackgroundRun();
            catch err
                mps.logWarning('关闭时取消后台运行', err);
            end
            try
                if app.TableCtl.needsSave()
                    app.saveSession();
                end
            catch err
                mps.logWarning('关闭时保存会话', err);
            end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end

        function loadFile(app, filePath, varargin)
            %LOADFILE Scan a .m file and populate the parameter table.
            %
            %   loadFile(file) restores <file>_session.json when available.
            %   loadFile(file, 'RestoreSession', false) starts fresh.
            restoreSession = true;
            for k = 1:2:numel(varargin)
                if k + 1 > numel(varargin), break; end
                if strcmpi(char(varargin{k}), 'RestoreSession')
                    value = varargin{k+1};
                    if ischar(value) || isstring(value)
                        restoreSession = ~strcmpi(char(value), 'off');
                    else
                        restoreSession = logical(value);
                    end
                end
            end
            filePath = char(filePath);
            if ~isfile(filePath)
                uialert(app.UIFigure, sprintf('文件不存在：\n%s', filePath), ...
                    '打开失败', 'Icon', 'error');
                return;
            end

            % If the user already edited values and switches to another
            % file, ask before throwing those edits away.
            if ~isempty(app.SourceFile) && ...
                    ~strcmp(app.SourceFile, filePath) && ...
                    ~isempty(app.Params) && any([app.Params.isChanged]) && ...
                    strcmp(app.UIFigure.Visible, 'on')
                choice = uiconfirm(app.UIFigure, ...
                    '当前有还没运行的新值，打开别的文件会丢失。是否继续？', ...
                    '未保存的修改', 'Options', {'继续', '取消'}, ...
                    'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(choice, '继续')
                    return;
                end
            end

            try
                p = mps.scan(filePath);
                manualParams = mps.readManualParams(filePath);
                if ~isempty(manualParams)
                    p = [p, manualParams];
                end
            catch err
                uialert(app.UIFigure, err.message, '扫描失败', 'Icon', 'error');
                return;
            end

            raw = fileread(filePath);
            raw = strrep(raw, sprintf('\r\n'), sprintf('\n'));
            raw = strrep(raw, sprintf('\r'), sprintf('\n'));
            app.SourceLines = regexp(raw, '\n', 'split');
            if ~isempty(app.SourceLines) && isempty(app.SourceLines{end})
                app.SourceLines(end) = [];
            end

            % A function file can be scanned and saved, but not executed by
            % run() without arguments.  Detect it for a clear status message.
            firstCode = '';
            for k = 1:numel(app.SourceLines)
                t = strtrim(app.SourceLines{k});
                if isempty(t) || t(1) == '%'
                    continue;
                end
                firstCode = t;
                break;
            end
            app.IsFunctionFile = ~isempty(regexp(firstCode, '^function\s', 'once'));

            % Resolve annotations: keep them when re-scanning the same file,
            % otherwise auto-load an <name>_annotations.json sidecar if it
            % exists (the file written by "生成注释 JSON").
            sameFile = strcmp(app.SourceFile, filePath);
            anns = struct([]);
            annFile = '';
            annMatched = 0;
            if sameFile && ~isempty(app.LastAnnotations)
                anns = app.LastAnnotations;
                annFile = app.AnnotationFile;
            else
                [folder, baseName] = fileparts(filePath);
                sidecar = fullfile(folder, [baseName '_annotations.json']);
                if isfile(sidecar)
                    try
                        candidate = mps.readAnnotations(sidecar);
                        if hasAnyAnnotation(candidate)
                            anns = candidate;
                            annFile = sidecar;
                        end
                    catch err
                        mps.logWarning('读取参数注释文件', err);
                    end
                end
            end

            app.SourceFile = filePath;
            app.EntryFile = '';
            app.ProjectMode = false;
            app.ProjectRoot = '';
            app.ProjectStamp = '';
            app.Params = p;
            app.LastAnnotations = struct([]);
            app.AnnotationFile = '';
            if ~isempty(anns)
                [app.Params, annStats] = mps.applyAnnotations(app.Params, anns);
                app.LastAnnotations = anns;
                app.AnnotationFile = annFile;
                annMatched = annStats.matched;
            end

            app.SourceStamp = mps.sourceStamp(filePath);
            app.TableCtl.setSource(filePath, app.SourceStamp);
            app.TableCtl.RecommendedMinScore = 3;
            app.TableCtl.resetHistory();
            sessionNote = '';
            if restoreSession
                session = mps.readSession(filePath);
                if ~isempty(session)
                    if mps.sameSourceStamp(session.stamp, app.SourceStamp)
                        preset = struct('name', '上次会话', ...
                            'values', session.values);
                        [app.Params, sessStats] = ...
                            mps.applyPreset(app.Params, preset);
                        sessionNote = sprintf( ...
                            '；已恢复上次未运行的修改 %d 项', ...
                            sessStats.matched);
                    else
                        try
                            delete(mps.sessionPath(filePath));
                        catch err
                            mps.logWarning('删除过期会话', err);
                        end
                        sessionNote = '；源文件已变化，未恢复上次修改';
                    end
                end
            end
            app.PresetCtl.loadFromDisk();
            app.Results.clear();
            app.TableCtl.clearSelection();

            app.FileLabel.Text = filePath;
            app.FileLabel.FontColor = [0.12 0.12 0.12];
            app.FileLabel.Tooltip = filePath;
            app.SourcePreview.Value = {''};
            app.LogArea.Value = {''};

            app.RescanButton.Enable = 'on';
            app.RunButton.Enable = 'on';
            if app.IsFunctionFile && isempty(app.EntryFile)
                app.RunButton.Enable = 'off';
            end
            app.EntryButton.Enable = 'on';
            app.SaveButton.Enable = 'on';
            app.ExportButton.Enable = 'on';
            if app.IsFunctionFile
                app.SweepButton.Enable = 'off';
                app.ManualButton.Enable = 'off';
                app.BackgroundCheck.Enable = 'off';
            else
                app.SweepButton.Enable = 'on';
                app.ManualButton.Enable = 'on';
                if license('test', 'Distrib_Computing_Toolbox')
                    app.BackgroundCheck.Enable = 'on';
                else
                    app.BackgroundCheck.Enable = 'off';
                end
            end
            app.AnnotateTemplateButton.Enable = 'on';
            app.ImportAnnotationButton.Enable = 'on';
            app.ClearAnnotationButton.Enable = 'on';
            app.LockButton.Enable = 'on';
            app.BulkButton.Enable = 'on';
            app.CompareButton.Enable = 'on';
            app.ReportButton.Enable = 'off';
            app.FolderButton.Enable = 'off';
            app.CloseFiguresButton.Enable = 'off';
            app.PlotButton.Enable = 'off';
            app.SavePlotButton.Enable = 'off';
            app.ExportCsvButton.Enable = 'off';

            app.refreshTable();
            nUse = sum([app.Params.use]);
            if ~isempty(app.LastAnnotations)
                annNote = sprintf('；已应用注释 %d 条（%s）', annMatched, app.AnnotationFile);
            else
                annNote = '';
            end
            if app.IsFunctionFile
                app.StatusLabel.Text = sprintf( ...
                    '已载入函数文件：识别 %d 个数字（%d 个推荐）%s%s。这是配置函数时，点“入口...”选择项目入口即可在临时副本中运行。', ...
                    numel(app.Params), nUse, annNote, sessionNote);
            else
                app.StatusLabel.Text = sprintf( ...
                    '已载入：识别 %d 个数字，其中 %d 个推荐参数%s%s。下一步：改“新值”后点“运行”。', ...
                    numel(app.Params), nUse, annNote, sessionNote);
            end
            drawnow;
        end

        function setParam(app, name, value)
            %SETPARAM Set a parameter by name (used by tests and automation).
            app.TableCtl.setParam(name, value);
        end

        function refreshTableView(app)
            %REFRESHTABLEVIEW Public bridge for controllers.
            app.refreshTable();
        end

        function setStatusText(app, message)
            %SETSTATUSTEXT Public bridge for controllers.
            app.StatusLabel.Text = char(message);
        end

        function backgroundProgress(app, message)
            %BACKGROUNDPROGRESS Public bridge for BackgroundRunManager.
            app.setBackgroundProgress(message);
        end

        function backgroundFinished(app, out, message)
            %BACKGROUNDFINISHED Public bridge for BackgroundRunManager.
            app.finishBackgroundRun(out, message);
        end

        function undoLastEdit(app)
            %UNDOLASTEDIT Restore the table state before the last change.
            app.TableCtl.undo();
        end

        function redoLastEdit(app)
            %REDOLASTEDIT Reapply the last undone change.
            app.TableCtl.redo();
        end

        function saveSession(app)
            %SAVESESSION Persist unsaved table edits next to the script.
            if app.TableCtl.needsSave()
                app.TableCtl.saveSession();
            end
        end

        function loadProject(app, entryFile)
            %LOADPROJECT Scan a project folder and classify params by file.
            app.loadProjectInternal(entryFile);
        end

        function setEntryPoint(app, entryFile)
            %SETENTRYPOINT Run this entry script with edits from SourceFile.
            app.setEntryPointInternal(entryFile);
        end

        function runCurrent(app)
            %RUNCURRENT Run the current script with the selected parameters.
            app.onRun();
        end

        function plotWorkspace(app, xName, yNames)
            %PLOTWORKSPACE Plot workspace variables in the 绘图 tab.
            app.Results.plotWorkspace(xName, yNames);
        end

        function saveCustomPlot(app)
            %SAVECUSTOMPLOT Save the current 绘图 tab figure and update the report.
            app.Results.savePlot(app.SourceFile, app.Params);
        end

        function exportCurveCsv(app)
            %EXPORTCURVECSV Write current X/Y selection to curve_data.csv.
            app.Results.exportCurveCsv();
        end

        function path = exportAnnotationTemplate(app, jsonPath)
            %EXPORTANNOTATIONTEMPLATE Write the annotation template JSON.
            path = app.AnnotationCtl.exportTemplate(jsonPath);
        end

        function stats = importAnnotations(app, jsonPath)
            %IMPORTANNOTATIONS Read and apply an annotation JSON.
            stats = app.AnnotationCtl.importFile(jsonPath);
        end

        function clearAnnotations(app)
            %CLEARANNOTATIONS Remove all in-memory annotations.
            app.AnnotationCtl.clear();
        end

        function toggleLock(app, name)
            %TOGGLELOCK Lock or unlock a parameter by name.
            app.TableCtl.toggleLock(name);
        end

        function saveCurrentPreset(app, name)
            %SAVECURRENTPRESET Store the current use/newValue/locked state.
            app.PresetCtl.saveCurrent(name);
        end

        function names = listPresets(app)
            %LISTPRESETS Names of the presets saved for the current file.
            names = app.PresetCtl.list();
        end

        function stats = applyPresetByName(app, name)
            %APPLYPRESETBYNAME Load a preset into the current parameter list.
            stats = app.PresetCtl.applyByName(name);
        end

        function summary = runSweepWithValues(app, names, valueLists, xName, yNames)
            %RUNSWEEPWITHVALUES Programmatic sweep (no dialog).
            %
            %   app.runSweepWithValues({'k','c'}, {1:2:9, [0.1 0.2]}, ...
            %                          't', {'y'})
            if nargin < 4
                xName = '';
            end
            if nargin < 5
                yNames = {};
            end
            summary = app.SweepCtl.runWithValues(names, valueLists, ...
                xName, yNames);
        end
    end

    methods
        function value = get.Params(app)
            value = app.TableCtl.Params;
        end

        function set.Params(app, value)
            app.TableCtl.Params = value;
        end

        function value = get.SelectedParams(app)
            value = app.TableCtl.SelectedParams;
        end

        function set.SelectedParams(app, value)
            app.TableCtl.SelectedParams = value;
        end

        function value = get.SourceLines(app)
            value = app.TableCtl.SourceLines;
        end

        function set.SourceLines(app, value)
            app.TableCtl.SourceLines = value;
        end

        function value = get.LastAnnotations(app)
            value = app.TableCtl.LastAnnotations;
        end

        function set.LastAnnotations(app, value)
            app.TableCtl.LastAnnotations = value;
        end

        function value = get.AnnotationFile(app)
            value = app.TableCtl.AnnotationFile;
        end

        function set.AnnotationFile(app, value)
            app.TableCtl.AnnotationFile = value;
        end
    end

    methods (Access = private)
        % -----------------------------------------------------------------
        function createUI(app)
            %CREATEUI Build controls in mps.buildAppUI and adopt handles.
            callbacks = app.uiCallbacks();
            handles = mps.buildAppUI(callbacks);
            names = fieldnames(handles);
            for k = 1:numel(names)
                app.(names{k}) = handles.(names{k});
            end
            app.Results = mps.ResultsController( ...
                app.UIFigure, app.FigureDrop, app.FigureImage, ...
                app.WorkspaceTable, app.XDrop, app.YList, app.UIAxes, ...
                app.PlotStatus, app.PlotButton, app.SavePlotButton, ...
                app.ExportCsvButton, app.ReportButton, app.StatusLabel);
            app.Save = mps.SaveController(app.UIFigure, app.StatusLabel);
            app.TableCtl = mps.ParameterTableController( ...
                app.UIFigure, app.Table, app.FilterDrop, app.SearchField, ...
                app.FileFilterDrop, app.CountLabel, ...
                app.SelectAllButton, app.SourcePreview, ...
                app.LockButton, app.UndoButton, app.RedoButton, ...
                app.AnnotationStatus, app.StatusLabel);
        end

        function callbacks = uiCallbacks(app)
            %UICALLBACKS Function handles used by mps.buildAppUI.
            callbacks = struct();
            callbacks.onOpen = @(s, e) app.onOpen();
            callbacks.onOpenProject = @(s, e) app.onOpenProject();
            callbacks.onRescan = @(s, e) app.onRescan();
            callbacks.onRun = @(s, e) app.onRun();
            callbacks.onSaveTuned = @(s, e) app.onSaveTuned();
            callbacks.onOpenReport = @(s, e) app.Results.openReport();
            callbacks.onOpenFolder = @(s, e) app.Results.openFolder();
            callbacks.onExportParams = @(s, e) app.onExportParams();
            callbacks.onCloseFigures = @(s, e) app.Results.closeFigures();
            callbacks.onRunHistory = @(s, e) app.HistoryCtl.onOpen();
            callbacks.onHelp = @(s, e) app.onHelp();
            callbacks.refreshTable = @() app.refreshTable();
            callbacks.onSelectAll = @(s, e) app.onSelectAll();
            callbacks.onReset = @(s, e) app.onReset();
            callbacks.onBulkEdit = @(s, e) app.onBulkEdit();
            callbacks.onWriteAnnotationTemplate = ...
                @(s, e) app.AnnotationCtl.onWrite();
            callbacks.onImportAnnotations = @(s, e) app.AnnotationCtl.onImport();
            callbacks.onClearAnnotations = @(s, e) app.AnnotationCtl.onClear();
            callbacks.onToggleLock = @(s, e) app.onToggleLock();
            callbacks.onSavePreset = @(s, e) app.PresetCtl.onSave();
            callbacks.onLoadPreset = @(s, e) app.PresetCtl.onLoad();
            callbacks.onDeletePreset = @(s, e) app.PresetCtl.onDelete();
            callbacks.onOpenSweep = @(s, e) app.SweepCtl.onOpen();
            callbacks.onAddManualParam = @(s, e) app.onAddManualParam();
            callbacks.onChooseEntry = @(s, e) app.onChooseEntry();
            callbacks.onCellEdit = @(e) app.onCellEdit([], e);
            callbacks.onCellSelect = @(e) app.onCellSelect([], e);
            callbacks.onOpenInEditor = @(e) app.onOpenInEditor(e);
            callbacks.undo = @() app.undoLastEdit();
            callbacks.redo = @() app.redoLastEdit();
            callbacks.showFigure = @() app.Results.showFigure();
            callbacks.onPlot = @(s, e) app.Results.onPlot();
            callbacks.onSavePlot = @(s, e) app.Results.savePlot( ...
                app.SourceFile, app.Params);
            callbacks.onExportCurve = @(s, e) app.Results.exportCurveCsv();
            callbacks.onKeyPress = @(e) app.onKeyPress(e);
            callbacks.onClose = @() app.onClose();
        end

        % -----------------------------------------------------------------
        function onKeyPress(app, event)
            %ONKEYPRESS F5 / Ctrl+Enter = run, Ctrl+O = open.
            if ~isstruct(event) || ~isfield(event, 'Key')
                return;
            end
            key = lower(event.Key);
            mods = {};
            if isfield(event, 'Modifier')
                if iscell(event.Modifier)
                    mods = event.Modifier;
                elseif ischar(event.Modifier)
                    mods = {event.Modifier};
                end
            end
            hasCtrl = any(strcmpi(mods, 'control'));
            hasShift = any(strcmpi(mods, 'shift'));
            if strcmp(key, 'f5') || (strcmp(key, 'return') && hasCtrl)
                app.onRun();
            elseif strcmp(key, 'o') && hasCtrl
                app.onOpen();
            elseif strcmp(key, 'b') && hasCtrl
                app.onBulkEdit();
            elseif strcmp(key, 'z') && hasCtrl
                if hasShift
                    app.redoLastEdit();
                else
                    app.undoLastEdit();
                end
            elseif strcmp(key, 'y') && hasCtrl
                app.redoLastEdit();
            end
        end

        function onOpen(app)
            if isempty(app.SourceFile)
                startDir = pwd;
            else
                startDir = fileparts(app.SourceFile);
            end
            [file, path] = uigetfile({'*.m', 'MATLAB 脚本 (*.m)'}, ...
                '选择 MATLAB 脚本', startDir);
            if isequal(file, 0)
                return;
            end
            app.loadFile(fullfile(path, file));
        end

        function onOpenProject(app)
            if isempty(app.SourceFile)
                startDir = pwd;
            else
                startDir = fileparts(app.SourceFile);
            end
            [file, path] = uigetfile({'*.m', '项目入口脚本 (*.m)'}, ...
                '选择项目入口脚本', startDir);
            if isequal(file, 0)
                return;
            end
            app.loadProject(fullfile(path, file));
        end

        function loadProjectInternal(app, entryFile)
            %LOADPROJECTINTERNAL Scan all .m files under the entry folder.
            session = mps.ProjectSession.load(entryFile);
            if ~session.ok
                uialert(app.UIFigure, session.error, '打开项目失败', ...
                    'Icon', 'error');
                return;
            end
            entryFile = session.entryFile;
            p = session.params;
            app.SourceFile = entryFile;
            app.EntryFile = entryFile;
            app.ProjectRoot = session.projectRoot;
            app.ProjectMode = true;
            app.ProjectStamp = session.projectStamp;
            app.IsFunctionFile = false;
            app.SourceLines = session.lines;
            app.Params = p;
            app.LastAnnotations = struct([]);
            app.AnnotationFile = '';
            app.SourceStamp = session.sourceStamp;
            app.TableCtl.setSource(entryFile, app.SourceStamp);
            app.TableCtl.RecommendedMinScore = 5;
            app.TableCtl.resetHistory();
            app.PresetCtl.loadFromDisk();
            app.Results.clear();
            app.TableCtl.clearSelection();
            app.SourcePreview.Value = {''};
            app.LogArea.Value = {''};
            app.FileLabel.Text = entryFile;
            app.FileLabel.FontColor = [0.12 0.12 0.12];
            app.FileLabel.Tooltip = entryFile;
            app.RescanButton.Enable = 'on';
            app.RunButton.Enable = 'on';
            app.SaveButton.Enable = 'off';
            app.ExportButton.Enable = 'on';
            app.SweepButton.Enable = 'on';
            app.ManualButton.Enable = 'off';
            app.EntryButton.Enable = 'on';
            app.AnnotateTemplateButton.Enable = 'on';
            app.ImportAnnotationButton.Enable = 'on';
            app.ClearAnnotationButton.Enable = 'on';
            app.LockButton.Enable = 'on';
            app.BulkButton.Enable = 'on';
            app.CompareButton.Enable = 'on';
            if license('test', 'Distrib_Computing_Toolbox')
                app.BackgroundCheck.Enable = 'on';
            else
                app.BackgroundCheck.Enable = 'off';
            end
            app.ReportButton.Enable = 'off';
            app.FolderButton.Enable = 'off';
            app.CloseFiguresButton.Enable = 'off';
            app.PlotButton.Enable = 'off';
            app.SavePlotButton.Enable = 'off';
            app.ExportCsvButton.Enable = 'off';
            app.refreshTable();
            labels = app.FileFilterDrop.Items(2:end);
            defaultLabel = mps.ProjectSession.defaultFilter(labels);
            if ~isempty(defaultLabel)
                app.FileFilterDrop.Value = defaultLabel;
                app.refreshTable();
            end
            app.StatusLabel.Text = sprintf( ...
                ['项目模式：入口 %s，扫描 %d 个 .m 文件，识别 %d 个参数。' ...
                 '默认显示 %s，可切换“文件”筛选。'], ...
                entryFile, numel(unique({p.sourceFile})), numel(p), ...
                app.FileFilterDrop.Value);
            drawnow;
        end

        function onChooseEntry(app)
            if isempty(app.SourceFile)
                uialert(app.UIFigure, '请先打开一个 .m 文件。', '没有文件', ...
                    'Icon', 'warning');
                return;
            end
            [file, path] = uigetfile({'*.m', 'MATLAB 脚本 (*.m)'}, ...
                '选择项目入口脚本', fileparts(app.SourceFile));
            if isequal(file, 0)
                return;
            end
            app.setEntryPoint(fullfile(path, file));
        end

        function setEntryPointInternal(app, entryFile)
            %SETENTRYPOINTINTERNAL Run entry script with edits from SourceFile.
            entryFile = char(entryFile);
            if ~isfile(entryFile)
                error('mps:App:missingEntry', '入口脚本不存在：%s', entryFile);
            end
            app.EntryFile = entryFile;
            app.RunButton.Enable = 'on';
            if license('test', 'Distrib_Computing_Toolbox')
                app.BackgroundCheck.Enable = 'on';
            end
            app.StatusLabel.Text = sprintf( ...
                '项目入口：%s（运行时会复制项目到临时目录并应用参数）', ...
                entryFile);
        end

        function onOpenInEditor(app, varargin)
            %ONOPENINEDITOR Jump to the selected parameter's source line.
            if ~isempty(varargin) && isstruct(varargin{1}) && ...
                    isfield(varargin{1}, 'Indices') && ...
                    ~isempty(varargin{1}.Indices)
                % Only the read-only 参数/行 columns open the editor; a
                % double-click on 新值 must keep working as cell editing.
                indices = varargin{1}.Indices;
                if size(indices, 2) < 2
                    return;
                end
                col = indices(1, 2);
                if ~ismember(col, [4 7])
                    return;
                end
            end
            if isempty(app.SourceFile) || isempty(app.SelectedParams)
                uialert(app.UIFigure, '请先在参数表里选中一行。', ...
                    '没有选中参数', 'Icon', 'warning');
                return;
            end
            idx = app.SelectedParams(end);
            lineNo = app.Params(idx).line;
            file = app.Params(idx).sourceFile;
            if isempty(file)
                file = app.SourceFile;
            end
            try
                matlab.desktop.editor.openAndGoToLine( ...
                    file, max(1, lineNo));
                app.StatusLabel.Text = sprintf( ...
                    '已在 MATLAB 编辑器中打开：%s 第 %d 行。', file, lineNo);
            catch
                try
                    edit(file);
                    app.StatusLabel.Text = sprintf( ...
                        '已打开源文件（未能定位到第 %d 行）。', lineNo);
                catch err
                    uialert(app.UIFigure, err.message, '打开失败', ...
                        'Icon', 'error');
                end
            end
        end

        function changed = sourceChanged(app)
            %SOURCECHANGED True when the file changed after it was scanned.
            changed = app.SourceCtl.sourceChanged();
        end

        function ok = ensureSourceCurrent(app, actionLabel)
            %ENSURESOURCECURRENT Ask before using stale line/column positions.
            ok = app.SourceCtl.ensureSourceCurrent(actionLabel);
        end

        function rescanKeepingEdits(app)
            %RESCANKEEPINGEDITS Re-scan and map old edits to the new table.
            app.SourceCtl.rescanKeepingEdits();
        end

        function onHelp(~)
            %ONHELP Show a short, plain-language quick start.
            mps.showQuickStart();
        end

        function onRescan(app)
            app.SourceCtl.rescanDiscardingEdits();
        end

        function onRun(app)
            if isempty(app.SourceFile)
                uialert(app.UIFigure, '请先打开一个 .m 文件。', '没有文件', ...
                    'Icon', 'warning');
                return;
            end
            if app.IsFunctionFile && isempty(app.EntryFile)
                uialert(app.UIFigure, ...
                    ['这是函数文件，不能直接运行。' ...
                     '如果它是配置函数，请点“入口...”选择项目入口脚本。'], ...
                    '需要项目入口', 'Icon', 'warning');
                return;
            end
            if app.Busy
                return;
            end
            if ~app.ensureSourceCurrent('运行')
                return;
            end
            if ~app.confirmInteractiveCalls('运行')
                return;
            end
            if app.BackgroundCheck.Value && ...
                    license('test', 'Distrib_Computing_Toolbox')
                app.startBackgroundRun();
                return;
            end

            app.setBusy(true);
            if strcmp(app.UIFigure.Visible, 'on')
                d = uiprogressdlg(app.UIFigure, 'Title', 'MATLAB Parameter Studio', ...
                    'Message', '准备参数...', 'Indeterminate', 'on');
            else
                d = [];   % hidden automation mode
            end
            oldHV = app.UIFigure.HandleVisibility;
            app.UIFigure.HandleVisibility = 'off';
            cleanupObj = onCleanup(@() app.finishRun(d, oldHV)); %#ok<NASGU>

            try
                % Close figures from the previous run so they do not pile up.
                if isfield(app.Results.LastRun, 'figureHandles')
                    old = app.Results.LastRun.figureHandles;
                    for k = 1:numel(old)
                        if isvalid(old(k))
                            close(old(k));
                        end
                    end
                end

                if app.ProjectMode || ...
                        (~isempty(app.EntryFile) && ...
                        ~strcmpi(app.EntryFile, app.SourceFile))
                    executor = mps.ProjectRunExecutor(app.SourceFile, ...
                        app.EntryFile, app.Params, ...
                        app.KeepFiguresCheck.Value);
                else
                    executor = mps.RunExecutor(app.SourceFile, app.Params, ...
                        app.KeepFiguresCheck.Value);
                end
                executor.MaxVariableMB = app.MaxVariableMB;
                executor.MaxTotalMB = app.MaxTotalMB;
                executor.LazyWorkspaceMB = app.LazyWorkspaceMB;
                executor.SaveFigFiles = app.SaveFigFiles;
                executor.FigureResolution = app.FigureResolution;
                executor.Progress = @(message) setProgress(d, message);
                out = executor.run();
                r = out.run;

                app.Results.OutputDir = out.outDir;
                app.Results.LastRun = r;
                app.Results.LastWorkspace = r.workspaceData;
                app.Results.LastReport = out.reportPath;
                app.Results.refreshAll();
                if isempty(r.log)
                    app.LogArea.Value = {''};
                else
                    app.LogArea.Value = splitlines(r.log);
                end
                app.ReportButton.Enable = 'on';
                app.FolderButton.Enable = 'on';
                app.CloseFiguresButton.Enable = 'on';
                app.CompareButton.Enable = 'on';

                if r.ok
                    app.StatusLabel.Text = sprintf( ...
                        '完成：%d 个参数参与，%d 张图，%d 个变量，耗时 %.2f s。可点“打开报告”查看结果。', ...
                        sum([app.Params.use]), numel(r.figures), ...
                        numel(r.workspace), r.elapsedSeconds);
                else
                    app.StatusLabel.Text = '运行失败，已生成错误报告。';
                    uialert(app.UIFigure, ...
                        '脚本运行出错。详情见“日志”标签和 HTML 报告。', ...
                        '运行失败', 'Icon', 'error');
                end
            catch err
                app.StatusLabel.Text = ['运行失败：' err.message];
                uialert(app.UIFigure, err.message, '运行失败', 'Icon', 'error');
            end
            clear cleanupObj;
        end

        function finishRun(app, d, oldHV)
            if ~isempty(d) && isvalid(d)
                delete(d);
            end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                app.UIFigure.HandleVisibility = oldHV;
            end
            app.setBusy(false);
        end

        % -----------------------------------------------------------------
        function startBackgroundRun(app)
            %STARTBACKGROUNDRUN Run one simulation on a PCT worker.
            if app.Busy
                return;
            end
            app.setBusy(true);

            % Close figures from the previous run.
            if isfield(app.Results.LastRun, 'figureHandles')
                old = app.Results.LastRun.figureHandles;
                for k = 1:numel(old)
                    if isvalid(old(k))
                        close(old(k));
                    end
                end
            end

            app.BackgroundMgr.RootPath = ...
                fileparts(fileparts(which('mps.App')));
            app.BackgroundMgr.BackgroundWorkers = app.BackgroundWorkers;
            app.BackgroundMgr.KeepParallelPool = app.KeepParallelPool;
            app.BackgroundMgr.TimeoutSeconds = app.RunTimeoutSeconds;
            try
                app.BackgroundMgr.start( ...
                    @(pool) mps.backgroundLaunch(app, pool));
            catch err
                app.finishBackgroundRun([], err.message);
            end
        end

        function finishBackgroundRun(app, out, errorMessage)
            %FINISHBACKGROUNDRUN Restore UI and publish a background result.
            if ~isempty(errorMessage)
                app.StatusLabel.Text = errorMessage;
                if strcmp(app.UIFigure.Visible, 'on')
                    uialert(app.UIFigure, errorMessage, '后台运行失败', ...
                        'Icon', 'error');
                end
                app.setBusy(false);
                return;
            end
            r = out.run;
            r.figureHandles = gobjects(0);
            app.Results.OutputDir = out.outDir;
            app.Results.LastRun = r;
            app.Results.LastWorkspace = r.workspaceData;
            app.Results.LastReport = out.reportPath;
            app.Results.refreshAll();
            if isempty(r.log)
                app.LogArea.Value = {''};
            else
                app.LogArea.Value = splitlines(r.log);
            end
            app.ReportButton.Enable = 'on';
            app.FolderButton.Enable = 'on';
            app.CloseFiguresButton.Enable = 'on';
            app.CompareButton.Enable = 'on';
            if r.ok
                app.StatusLabel.Text = sprintf( ...
                    '后台完成：%d 个参数参与，%d 张图，%d 个变量，耗时 %.2f s。', ...
                    sum([app.Params.use]), numel(r.figures), ...
                    numel(r.workspace), r.elapsedSeconds);
            else
                app.StatusLabel.Text = '后台运行失败，已生成错误报告。';
                if strcmp(app.UIFigure.Visible, 'on')
                    uialert(app.UIFigure, ...
                        '脚本运行出错。详情见“日志”标签和 HTML 报告。', ...
                        '运行失败', 'Icon', 'error');
                end
            end
            app.setBusy(false);
        end

        function cancelBackgroundRun(app)
            if ~isempty(app.BackgroundMgr)
                app.BackgroundMgr.cancel();
            end
        end

        function setBackgroundProgress(app, message)
            if ~isempty(app.BackgroundMgr)
                app.BackgroundMgr.setProgress(message);
            end
        end

        % -----------------------------------------------------------------
        function pushUndo(app)
            app.TableCtl.pushUndo();
        end

        function refreshTable(app)
            app.TableCtl.refresh();
        end

        function onCellEdit(app, ~, event)
            app.TableCtl.onCellEdit(event);
        end

        function onCellSelect(app, ~, event)
            app.TableCtl.onCellSelect(event);
        end

        function onSelectAll(app)
            app.TableCtl.onSelectAll();
        end

        function onReset(app)
            app.TableCtl.onReset();
        end

        function onBulkEdit(app)
            app.TableCtl.onBulkEdit();
        end
        function onToggleLock(app)
            app.TableCtl.onToggleLock();
        end

        % ---- Batch sweep ------------------------------------------
        function onAddManualParam(app)
            if isempty(app.SourceFile)
                uialert(app.UIFigure, '请先打开一个 .m 文件。', '没有文件', ...
                    'Icon', 'warning');
                return;
            end
            if app.ProjectMode
                uialert(app.UIFigure, ...
                    '项目模式暂不支持手动参数；请在有明确源文件的单文件模式下使用。', ...
                    '项目模式', 'Icon', 'warning');
                return;
            end
            if app.IsFunctionFile
                uialert(app.UIFigure, ...
                    '函数文件不能直接运行，也不支持手动添加参数。', ...
                    '无法添加', 'Icon', 'warning');
                return;
            end
            editIdx = 0;
            defaults = {'', '', '', ''};
            if numel(app.SelectedParams) == 1
                candidate = app.SelectedParams(1);
                if isfield(app.Params(candidate), 'manual') && ...
                        logical(app.Params(candidate).manual)
                    editIdx = candidate;
                    defaults = {app.Params(candidate).name, ...
                        app.Params(candidate).newValue, ...
                        app.Params(candidate).description, ...
                        app.Params(candidate).unit};
                end
            end
            answer = inputdlg({ ...
                '参数名（合法 MATLAB 变量名）', ...
                '初始值（数值表达式）', ...
                '说明（可选）', ...
                '单位（可选）'}, '手动参数', [1 52; 1 52; 2 52; 1 32], ...
                defaults);
            if isempty(answer)
                return;
            end
            name = strtrim(answer{1});
            value = strtrim(answer{2});
            duplicate = find(strcmp({app.Params.name}, name));
            duplicate = duplicate(duplicate ~= editIdx);
            if ~isempty(duplicate)
                uialert(app.UIFigure, ...
                    sprintf('参数“%s”已经存在，请直接编辑原参数。', name), ...
                    '参数已存在', 'Icon', 'warning');
                return;
            end
            try
                p = mps.makeManualParam(app.SourceFile, name, value, ...
                    answer{3}, answer{4});
            catch err
                uialert(app.UIFigure, err.message, '保存失败', ...
                    'Icon', 'error');
                return;
            end
            app.pushUndo();
            if editIdx > 0
                p.use = app.Params(editIdx).use;
                p.locked = app.Params(editIdx).locked;
                app.Params(editIdx) = p;
                action = '已更新';
            else
                app.Params(end+1) = p;
                action = '已添加';
            end
            app.refreshTable();
            mps.writeManualParams(app.SourceFile, app.Params);
            app.StatusLabel.Text = sprintf( ...
                '%s手动参数：%s = %s（下次打开会自动恢复）', ...
                action, p.name, p.newValue);
        end

        function ok = confirmInteractiveCalls(app, actionLabel)
            ok = true;
            calls = mps.detectInteractiveCalls(app.SourceFile);
            if isempty(calls)
                return;
            end
            names = unique({calls.name});
            list = strjoin(names, ', ');
            if ~strcmp(app.UIFigure.Visible, 'on')
                app.StatusLabel.Text = sprintf( ...
                    '脚本包含交互调用（%s），已阻止%s。', list, actionLabel);
                ok = false;
                return;
            end
            choice = uiconfirm(app.UIFigure, sprintf( ...
                ['脚本包含可能等待输入的调用：%s。\n\n' ...
                 '运行后界面可能停在这些语句上。是否仍然%s？'], ...
                list, actionLabel), '脚本可能等待输入', ...
                'Options', {'仍然继续', '取消'}, ...
                'DefaultOption', 2, 'CancelOption', 2);
            ok = strcmp(choice, '仍然继续');
        end

        % -----------------------------------------------------------------
        function onSaveTuned(app)
            if isempty(app.SourceFile)
                return;
            end
            if app.ProjectMode
                uialert(app.UIFigure, ...
                    ['项目模式一次修改多个文件，暂不支持合并保存为单个 _tuned.m。' ...
                     '请使用参数集/JSON 记录，或分别打开各文件保存。'], ...
                    '项目模式不支持单文件保存', 'Icon', 'warning');
                return;
            end
            if ~app.ensureSourceCurrent('保存')
                return;
            end
            app.Save.saveTuned(app.SourceFile, app.Params);
        end

        function onExportParams(app)
            if isempty(app.SourceFile)
                return;
            end
            app.Save.exportParams(app.SourceFile, app.Params);
        end
        function onClose(app)
            try
                app.cancelBackgroundRun();
            catch err
                mps.logWarning('关闭时取消后台运行', err);
            end
            try
                if app.TableCtl.needsSave()
                    app.saveSession();
                end
            catch err
                mps.logWarning('关闭时保存会话', err);
            end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                app.UIFigure.UserData = [];
                delete(app.UIFigure);
            end
        end

        function setBusy(app, b)
            app.Busy = b;
            btns = [app.OpenButton, app.RescanButton, app.RunButton, ...
                app.SaveButton, app.ReportButton, app.FolderButton, ...
                app.ExportButton, app.CloseFiguresButton, ...
                app.SelectAllButton, app.ResetButton, ...
                app.AnnotateTemplateButton, app.ImportAnnotationButton, ...
                app.ClearAnnotationButton, app.LockButton, ...
                app.CompareButton, app.PresetSaveButton, ...
                app.PresetLoadButton, app.PresetDeleteButton, ...
                app.SweepButton, app.BulkButton, app.ManualButton, ...
                app.EntryButton, app.UndoButton, app.RedoButton, ...
                app.PlotButton, app.SavePlotButton, app.ExportCsvButton, ...
                app.OpenReportInline];
            for k = 1:numel(btns)
                if isvalid(btns(k))
                    if b
                        btns(k).Enable = 'off';
                    else
                        btns(k).Enable = 'on';
                    end
                end
            end
            if b
                app.KeepFiguresCheck.Enable = 'off';
                app.BackgroundCheck.Enable = 'off';
                app.Table.Enable = 'off';
                app.FilterDrop.Enable = 'off';
                app.SearchField.Enable = 'off';
            else
                app.KeepFiguresCheck.Enable = 'on';
                app.Table.Enable = 'on';
                app.FilterDrop.Enable = 'on';
                app.SearchField.Enable = 'on';
                if ~isempty(app.SourceFile) && ...
                        (~app.IsFunctionFile || ~isempty(app.EntryFile)) && ...
                        license('test', 'Distrib_Computing_Toolbox')
                    app.BackgroundCheck.Enable = 'on';
                else
                    app.BackgroundCheck.Enable = 'off';
                end
            end
            if ~b
                % Restore the buttons that depend on state.
                if isempty(app.SourceFile)
                    app.RescanButton.Enable = 'off';
                    app.RunButton.Enable = 'off';
                    app.SaveButton.Enable = 'off';
                    app.ExportButton.Enable = 'off';
                    app.AnnotateTemplateButton.Enable = 'off';
                    app.ImportAnnotationButton.Enable = 'off';
                    app.ClearAnnotationButton.Enable = 'off';
                    app.LockButton.Enable = 'off';
                    app.BulkButton.Enable = 'off';
                    app.CompareButton.Enable = 'off';
                    app.PresetSaveButton.Enable = 'off';
                    app.PresetLoadButton.Enable = 'off';
                    app.PresetDeleteButton.Enable = 'off';
                    app.SweepButton.Enable = 'off';
                    app.ManualButton.Enable = 'off';
                    app.EntryButton.Enable = 'off';
                elseif app.IsFunctionFile && isempty(app.EntryFile)
                    app.RunButton.Enable = 'off';
                    app.SweepButton.Enable = 'off';
                    app.ManualButton.Enable = 'off';
                end
                if ~isempty(app.SourceFile)
                    app.PresetSaveButton.Enable = 'on';
                    if isempty(app.PresetCtl.Presets)
                        app.PresetLoadButton.Enable = 'off';
                        app.PresetDeleteButton.Enable = 'off';
                    else
                        app.PresetLoadButton.Enable = 'on';
                        app.PresetDeleteButton.Enable = 'on';
                    end
                    if ~app.IsFunctionFile
                        app.SweepButton.Enable = 'on';
                        if ~app.ProjectMode
                            app.ManualButton.Enable = 'on';
                        end
                    end
                    if app.ProjectMode
                        app.SaveButton.Enable = 'off';
                        app.ManualButton.Enable = 'off';
                    end
                end
                if isempty(app.SourceFile)
                    app.CompareButton.Enable = 'off';
                else
                    app.CompareButton.Enable = 'on';
                end
                if isempty(app.Results.LastReport)
                    app.ReportButton.Enable = 'off';
                end
                if isempty(app.Results.OutputDir)
                    app.FolderButton.Enable = 'off';
                end
                if ~isfield(app.Results.LastRun, 'figures') || isempty(app.Results.LastRun.figures)
                    app.CloseFiguresButton.Enable = 'off';
                end
                hasWorkspaceFile = isfield(app.Results.LastRun, 'matFile') && ...
                    ~isempty(app.Results.LastRun.matFile) && ...
                    isfile(app.Results.LastRun.matFile);
                if ~hasWorkspaceFile && ...
                        (~isstruct(app.Results.LastWorkspace) || ...
                        isempty(fieldnames(app.Results.LastWorkspace)))
                    app.PlotButton.Enable = 'off';
                    app.SavePlotButton.Enable = 'off';
                    app.ExportCsvButton.Enable = 'off';
                end
            end
            app.TableCtl.setBusy(b);
            drawnow;
        end
    end
end

% -------------------------------------------------------------------------
function setProgress(d, msg)
%SETPROGRESS Update a progress dialog if it exists, then flush the UI.
    if ~isempty(d) && isvalid(d)
        d.Message = msg;
    end
    drawnow;
end

% -------------------------------------------------------------------------
function tf = hasAnyAnnotation(anns)
%HASANYANNOTATION True when at least one annotation has content.
    tf = false;
    for k = 1:numel(anns)
        if ~isempty(anns(k).description) || ~isempty(anns(k).unit)
            tf = true;
            return;
        end
    end
end
