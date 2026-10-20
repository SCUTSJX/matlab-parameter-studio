classdef App < handle
%APP The MATLAB Parameter Studio user interface.
%
%   app = mps.App() creates the window.  Most users should call the
%   MatlabParameterStudio launcher instead.

    properties
        UIFigure
        SourceFile = ''
        SourceStamp = struct()
        Results
        MaxVariableMB = 100
        MaxTotalMB = 512
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
        FilterDrop, SearchField, CountLabel
        Table, SourcePreview
        FigureDrop, FigureImage
        WorkspaceTable
        XDrop, YList, PlotStatus, UIAxes
        LogArea
        OpenButton, RescanButton, RunButton, SaveButton, ReportButton
        FolderButton, ExportButton, CloseFiguresButton, HelpButton
        SelectAllButton, ResetButton, PlotButton, SavePlotButton, ExportCsvButton
        OpenReportInline
        AnnotationStatus, AnnotateTemplateButton, ImportAnnotationButton
        ClearAnnotationButton, LockButton, CompareButton, KeepFiguresCheck
        PresetDrop, PresetNameField, PresetSaveButton, PresetLoadButton
        PresetDeleteButton, SweepButton, BulkButton, ManualButton
        UndoButton, RedoButton
        IsFunctionFile = false
        Save
        TableCtl
        Presets = struct([])
        PresetsFile = ''
        Busy = false
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
            app.createUI();
            if strcmpi(visible, 'off')
                app.UIFigure.Visible = 'off';
            end
            app.UIFigure.UserData = app;
        end

        function delete(app)
            try
                if app.TableCtl.needsSave()
                    app.saveSession();
                end
            catch
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
                    catch
                    end
                end
            end

            app.SourceFile = filePath;
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
                        catch
                        end
                        sessionNote = '；源文件已变化，未恢复上次修改';
                    end
                end
            end
            app.loadPresetsFromDisk();
            app.Results.clear();
            app.TableCtl.clearSelection();

            app.FileLabel.Text = filePath;
            app.FileLabel.FontColor = [0.12 0.12 0.12];
            app.FileLabel.Tooltip = filePath;
            app.SourcePreview.Value = {''};
            app.LogArea.Value = {''};

            app.RescanButton.Enable = 'on';
            app.RunButton.Enable = 'on';
            if app.IsFunctionFile
                app.RunButton.Enable = 'off';
            end
            app.SaveButton.Enable = 'on';
            app.ExportButton.Enable = 'on';
            if app.IsFunctionFile
                app.SweepButton.Enable = 'off';
                app.ManualButton.Enable = 'off';
            else
                app.SweepButton.Enable = 'on';
                app.ManualButton.Enable = 'on';
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
                    '已载入函数文件：识别 %d 个数字（%d 个推荐），可保存调参后的函数，但不能直接运行%s%s。', ...
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
            mps.writeAnnotationTemplate(app.SourceFile, app.Params, jsonPath);
            path = jsonPath;
        end

        function stats = importAnnotations(app, jsonPath)
            %IMPORTANNOTATIONS Read and apply an annotation JSON.
            anns = mps.readAnnotations(jsonPath);
            app.pushUndo();
            [app.Params, stats] = mps.applyAnnotations(app.Params, anns);
            app.LastAnnotations = anns;
            app.AnnotationFile = jsonPath;
            app.refreshTable();
        end

        function clearAnnotations(app)
            %CLEARANNOTATIONS Remove all in-memory annotations.
            app.onClearAnnotations();
        end

        function toggleLock(app, name)
            %TOGGLELOCK Lock or unlock a parameter by name.
            app.TableCtl.toggleLock(name);
        end

        function saveCurrentPreset(app, name)
            %SAVECURRENTPRESET Store the current use/newValue/locked state.
            if isempty(app.SourceFile)
                error('mps:App:noFile', '请先打开一个 .m 文件。');
            end
            app.Presets = mps.savePreset(app.SourceFile, name, app.Params);
            app.refreshPresets();
        end

        function names = listPresets(app)
            %LISTPRESETS Names of the presets saved for the current file.
            names = {};
            if ~isempty(app.Presets)
                names = {app.Presets.name};
            end
        end

        function stats = applyPresetByName(app, name)
            %APPLYPRESETBYNAME Load a preset into the current parameter list.
            idx = find(strcmp({app.Presets.name}, name), 1);
            if isempty(idx)
                error('mps:App:presetNotFound', '找不到参数集：%s', name);
            end
            app.pushUndo();
            [app.Params, stats] = mps.applyPreset(app.Params, app.Presets(idx));
            app.refreshTable();
        end

        function summary = runSweepWithValues(app, names, valueLists, xName, yNames)
            %RUNSWEEPWITHVALUES Programmatic sweep (no dialog).
            %
            %   app.runSweepWithValues({'k','c'}, {1:2:9, [0.1 0.2]}, ...
            %                          't', {'y'})
            if ischar(names) || isstring(names)
                names = cellstr(names);
            end
            if isnumeric(valueLists)
                valueLists = {valueLists};
            end
            activeIdx = [];
            for k = 1:numel(names)
                idx = find(strcmp({app.Params.name}, names{k}), 1);
                if isempty(idx)
                    error('mps:App:paramNotFound', '找不到参数：%s', names{k});
                end
                activeIdx(end+1) = idx; %#ok<AGROW>
            end
            if nargin < 4 || isempty(xName)
                xName = '';
            end
            if nargin < 5 || isempty(yNames)
                yNames = {};
            end
            overlay = ~isempty(xName) && ~isempty(yNames);
            summary = app.runSweep(activeIdx, valueLists, overlay, ...
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
                app.CountLabel, app.SelectAllButton, app.SourcePreview, ...
                app.LockButton, app.UndoButton, app.RedoButton, ...
                app.AnnotationStatus, app.StatusLabel);
        end

        function callbacks = uiCallbacks(app)
            %UICALLBACKS Function handles used by mps.buildAppUI.
            callbacks = struct();
            callbacks.onOpen = @(s, e) app.onOpen();
            callbacks.onRescan = @(s, e) app.onRescan();
            callbacks.onRun = @(s, e) app.onRun();
            callbacks.onSaveTuned = @(s, e) app.onSaveTuned();
            callbacks.onOpenReport = @(s, e) app.Results.openReport();
            callbacks.onOpenFolder = @(s, e) app.Results.openFolder();
            callbacks.onExportParams = @(s, e) app.onExportParams();
            callbacks.onCloseFigures = @(s, e) app.Results.closeFigures();
            callbacks.onRunHistory = @(s, e) app.onRunHistory();
            callbacks.onHelp = @(s, e) app.onHelp();
            callbacks.refreshTable = @() app.refreshTable();
            callbacks.onSelectAll = @(s, e) app.onSelectAll();
            callbacks.onReset = @(s, e) app.onReset();
            callbacks.onBulkEdit = @(s, e) app.onBulkEdit();
            callbacks.onWriteAnnotationTemplate = ...
                @(s, e) app.onWriteAnnotationTemplate();
            callbacks.onImportAnnotations = @(s, e) app.onImportAnnotations();
            callbacks.onClearAnnotations = @(s, e) app.onClearAnnotations();
            callbacks.onToggleLock = @(s, e) app.onToggleLock();
            callbacks.onSavePreset = @(s, e) app.onSavePreset();
            callbacks.onLoadPreset = @(s, e) app.onLoadPreset();
            callbacks.onDeletePreset = @(s, e) app.onDeletePreset();
            callbacks.onOpenSweep = @(s, e) app.onOpenSweep();
            callbacks.onAddManualParam = @(s, e) app.onAddManualParam();
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
                if ~ismember(col, [3 6])
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
            try
                matlab.desktop.editor.openAndGoToLine( ...
                    app.SourceFile, max(1, lineNo));
                app.StatusLabel.Text = sprintf( ...
                    '已在 MATLAB 编辑器中打开：第 %d 行。', lineNo);
            catch
                try
                    edit(app.SourceFile);
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
            changed = false;
            if isempty(app.SourceFile) || isempty(fieldnames(app.SourceStamp))
                return;
            end
            try
                current = mps.sourceStamp(app.SourceFile);
                changed = ~mps.sameSourceStamp(app.SourceStamp, current);
            catch
                changed = true;
            end
        end

        function ok = ensureSourceCurrent(app, actionLabel)
            %ENSURESOURCECURRENT Ask before using stale line/column positions.
            ok = true;
            if ~app.sourceChanged()
                return;
            end
            if ~strcmp(app.UIFigure.Visible, 'on')
                app.StatusLabel.Text = sprintf( ...
                    '源文件已被外部修改，无法%s；请先重新扫描。', actionLabel);
                ok = false;
                return;
            end
            choice = uiconfirm(app.UIFigure, sprintf( ...
                ['源文件在扫描后被外部修改了。\n\n' ...
                 '继续%s可能把值写到旧的行号位置。建议先重新扫描并保留修改。'], ...
                actionLabel), '源文件已变化', ...
                'Options', {'重新扫描并保留修改', '仍然继续', '取消'}, ...
                'DefaultOption', 1, 'CancelOption', 3);
            switch choice
                case '重新扫描并保留修改'
                    app.rescanKeepingEdits();
                case '仍然继续'
                    % The user explicitly accepts the stale positions.
                otherwise
                    ok = false;
            end
        end

        function rescanKeepingEdits(app)
            %RESCANKEEPINGEDITS Re-scan and map old edits to the new table.
            if isempty(app.SourceFile)
                return;
            end
            oldParams = app.Params;
            oldAnnotations = app.LastAnnotations;
            oldAnnotationFile = app.AnnotationFile;
            try
                delete(mps.sessionPath(app.SourceFile));
            catch
            end
            app.loadFile(app.SourceFile, 'RestoreSession', false);
            preset = struct('name', '重扫前修改', ...
                'values', mps.paramsToValues(oldParams));
            [app.Params, stats] = mps.applyPreset(app.Params, preset);
            if ~isempty(oldAnnotations)
                [app.Params, ~] = mps.applyAnnotations( ...
                    app.Params, oldAnnotations);
                app.LastAnnotations = oldAnnotations;
                app.AnnotationFile = oldAnnotationFile;
            end
            app.TableCtl.markDirty();
            app.refreshTable();
            app.StatusLabel.Text = sprintf( ...
                '已重新扫描并保留修改：匹配 %d，重名跳过 %d，未匹配 %d。', ...
                stats.matched, stats.ambiguous, stats.unmatched);
        end

        function onHelp(~)
            %ONHELP Show a short, plain-language quick start.
            mps.showQuickStart();
        end

        function onRescan(app)
            if isempty(app.SourceFile)
                return;
            end
            if any([app.Params.isChanged])
                choice = uiconfirm(app.UIFigure, ...
                    '重新扫描会丢弃当前修改的新值。是否继续？', ...
                    '重新扫描', 'Options', {'继续', '取消'}, ...
                    'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(choice, '继续')
                    return;
                end
            end
            try
                delete(mps.sessionPath(app.SourceFile));
            catch
            end
            app.loadFile(app.SourceFile, 'RestoreSession', false);
        end

        function onRun(app)
            if isempty(app.SourceFile)
                uialert(app.UIFigure, '请先打开一个 .m 文件。', '没有文件', ...
                    'Icon', 'warning');
                return;
            end
            if app.IsFunctionFile
                uialert(app.UIFigure, ...
                    '这是函数文件，不能直接运行。请打开调用它的脚本，再调参运行。', ...
                    '无法直接运行', 'Icon', 'warning');
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

                executor = mps.RunExecutor(app.SourceFile, app.Params, ...
                    app.KeepFiguresCheck.Value);
                executor.MaxVariableMB = app.MaxVariableMB;
                executor.MaxTotalMB = app.MaxTotalMB;
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
        function onWriteAnnotationTemplate(app)
            if isempty(app.SourceFile)
                uialert(app.UIFigure, '请先打开一个 .m 文件。', '没有文件', ...
                    'Icon', 'warning');
                return;
            end
            [~, base] = fileparts(app.SourceFile);
            defaultName = fullfile(fileparts(app.SourceFile), ...
                [base '_annotations.json']);
            [file, path] = uiputfile({'*.json', 'JSON 文件 (*.json)'}, ...
                '生成注释模板 JSON', defaultName);
            if isequal(file, 0)
                return;
            end
            target = fullfile(path, file);
            try
                mps.writeAnnotationTemplate(app.SourceFile, ...
                    app.Params, target);
            catch err
                uialert(app.UIFigure, err.message, '生成失败', 'Icon', 'error');
                return;
            end
            app.StatusLabel.Text = sprintf('注释模板已生成：%s', target);
            uialert(app.UIFigure, sprintf( ...
                ['注释模板已生成：\n%s\n\n' ...
                 '使用方法：把该 JSON 发给 AI（或自己填写），让 AI 为每个参数的 ' ...
                 'description（含义）和 unit（单位）赋值，然后回到本应用点“导入注释”。\n\n' ...
                 '重新打开同一个 .m 文件时，如果旁边存在 <文件名>_annotations.json，' ...
                 '会自动载入。'], target), '生成成功', 'Icon', 'info');
        end

        function onImportAnnotations(app)
            if isempty(app.SourceFile)
                uialert(app.UIFigure, '请先打开一个 .m 文件。', '没有文件', ...
                    'Icon', 'warning');
                return;
            end
            [file, path] = uigetfile({'*.json', 'JSON 文件 (*.json)'}, ...
                '导入注释 JSON', fileparts(app.SourceFile));
            if isequal(file, 0)
                return;
            end
            target = fullfile(path, file);
            try
                anns = mps.readAnnotations(target);
            catch err
                uialert(app.UIFigure, err.message, '导入失败', 'Icon', 'error');
                return;
            end
            app.pushUndo();
            [app.Params, stats] = mps.applyAnnotations(app.Params, anns);
            app.LastAnnotations = anns;
            app.AnnotationFile = target;
            app.refreshTable();
            msg = sprintf(['已读取 %d 条注释：\n' ...
                '  匹配到参数：%d\n  重名无法匹配：%d\n  未匹配：%d\n  空注释跳过：%d'], ...
                numel(anns), stats.matched, stats.ambiguous, ...
                stats.unmatched, stats.skipped);
            app.StatusLabel.Text = sprintf('已导入注释：匹配 %d / %d 条（%s）', ...
                stats.matched, numel(anns), target);
            if stats.matched == 0 && stats.skipped < numel(anns)
                uialert(app.UIFigure, [msg, sprintf('\n\n提示：注释里的变量名需要和“参数”列一致；id 匹配最准确。')], ...
                    '没有匹配到参数', 'Icon', 'warning');
            else
                uialert(app.UIFigure, msg, '导入注释', 'Icon', 'info');
            end
        end

        function onClearAnnotations(app)
            app.pushUndo();
            for k = 1:numel(app.Params)
                app.Params(k).description = '';
                app.Params(k).unit = '';
            end
            app.LastAnnotations = struct([]);
            app.AnnotationFile = '';
            app.refreshTable();
            app.StatusLabel.Text = '已清空当前参数上的注释。';
        end

        function onToggleLock(app)
            app.TableCtl.onToggleLock();
        end

        % ---- Parameter presets -------------------------------------
        function loadPresetsFromDisk(app)
            app.Presets = struct([]);
            app.PresetsFile = '';
            if ~isempty(app.SourceFile)
                app.PresetsFile = mps.presetsPath(app.SourceFile);
                try
                    app.Presets = mps.readPresets(app.SourceFile);
                catch
                    app.Presets = struct([]);
                end
            end
            app.refreshPresets();
        end

        function refreshPresets(app)
            names = {};
            if ~isempty(app.Presets)
                names = {app.Presets.name};
            end
            if isempty(names)
                app.PresetDrop.Items = {'(无参数集)'};
                app.PresetDrop.Value = '(无参数集)';
                app.PresetLoadButton.Enable = 'off';
                app.PresetDeleteButton.Enable = 'off';
                return;
            end
            app.PresetDrop.Items = names;
            if ~any(strcmp(names, app.PresetDrop.Value))
                app.PresetDrop.Value = names{1};
            end
            if isempty(app.SourceFile)
                app.PresetLoadButton.Enable = 'off';
                app.PresetDeleteButton.Enable = 'off';
            else
                app.PresetLoadButton.Enable = 'on';
                app.PresetDeleteButton.Enable = 'on';
            end
        end

        function onSavePreset(app)
            if isempty(app.SourceFile)
                uialert(app.UIFigure, '请先打开一个 .m 文件。', '没有文件', ...
                    'Icon', 'warning');
                return;
            end
            name = strtrim(char(app.PresetNameField.Value));
            if isempty(name) && ~isempty(app.Presets)
                if ~strcmp(app.PresetDrop.Value, '(无参数集)')
                    name = app.PresetDrop.Value;
                end
            end
            if isempty(name)
                uialert(app.UIFigure, ...
                    '请输入参数集名称，或在下拉框里选择一个已有参数集覆盖保存。', ...
                    '缺少名称', 'Icon', 'warning');
                return;
            end
            exists = any(strcmp({app.Presets.name}, name));
            if exists
                choice = uiconfirm(app.UIFigure, ...
                    sprintf('参数集“%s”已存在，是否覆盖？', name), ...
                    '覆盖参数集', 'Options', {'覆盖', '取消'}, ...
                    'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(choice, '覆盖')
                    return;
                end
            end
            try
                app.Presets = mps.savePreset(app.SourceFile, name, app.Params);
            catch err
                uialert(app.UIFigure, err.message, '保存失败', 'Icon', 'error');
                return;
            end
            app.PresetNameField.Value = '';
            app.refreshPresets();
            app.PresetDrop.Value = name;
            app.StatusLabel.Text = sprintf('已保存参数集：%s（%s）', ...
                name, app.PresetsFile);
        end

        function onLoadPreset(app)
            if isempty(app.Presets) || isempty(app.SourceFile)
                uialert(app.UIFigure, '还没有可载入的参数集。', ...
                    '没有参数集', 'Icon', 'warning');
                return;
            end
            name = app.PresetDrop.Value;
            idx = find(strcmp({app.Presets.name}, name), 1);
            if isempty(idx)
                return;
            end
            app.pushUndo();
            try
                [app.Params, stats] = mps.applyPreset(app.Params, app.Presets(idx));
            catch err
                uialert(app.UIFigure, err.message, '载入失败', 'Icon', 'error');
                return;
            end
            app.refreshTable();
            app.StatusLabel.Text = sprintf( ...
                '已载入参数集：%s（匹配 %d，重名跳过 %d，未匹配 %d）', ...
                name, stats.matched, stats.ambiguous, stats.unmatched);
            if stats.unmatched > 0 || stats.ambiguous > 0
                uialert(app.UIFigure, sprintf( ...
                    ['载入“%s”：匹配 %d，重名跳过 %d，未匹配 %d。\n\n' ...
                     '未匹配通常是因为脚本改过变量名或行号；参数集里的 id ' ...
                     '保留的是保存时的位置。'], name, stats.matched, ...
                    stats.ambiguous, stats.unmatched), ...
                    '载入参数集', 'Icon', 'warning');
            end
        end

        function onDeletePreset(app)
            if isempty(app.Presets)
                return;
            end
            name = app.PresetDrop.Value;
            choice = uiconfirm(app.UIFigure, ...
                sprintf('删除参数集“%s”？', name), '删除参数集', ...
                'Options', {'删除', '取消'}, ...
                'DefaultOption', 2, 'CancelOption', 2);
            if ~strcmp(choice, '删除')
                return;
            end
            keep = ~strcmp({app.Presets.name}, name);
            app.Presets = app.Presets(keep);
            try
                mps.writePresets(app.SourceFile, app.Presets);
            catch err
                uialert(app.UIFigure, err.message, '删除失败', 'Icon', 'error');
                return;
            end
            app.refreshPresets();
            app.StatusLabel.Text = sprintf('已删除参数集：%s', name);
        end

        % ---- Batch sweep ------------------------------------------
        function onOpenSweep(app)
            if isempty(app.SourceFile)
                uialert(app.UIFigure, '请先打开一个 .m 文件。', '没有文件', ...
                    'Icon', 'warning');
                return;
            end
            if app.IsFunctionFile
                uialert(app.UIFigure, ...
                    '这是函数文件，不能直接扫描运行。请打开调用它的脚本。', ...
                    '无法批量扫描', 'Icon', 'warning');
                return;
            end
            if app.Busy
                return;
            end
            dlg = mps.SweepDialog(app.Params, app.Results.LastWorkspace);
            uiwait(dlg.UIFigure);
            result = dlg.Result;
            delete(dlg);
            if ~isstruct(result) || ~isfield(result, 'activeIdx') || ...
                    isempty(result.activeIdx)
                return;   % cancelled
            end
            app.runSweep(result.activeIdx, result.values, ...
                result.overlay, result.xName, result.yNames, ...
                result.parallel, result.maxScenarios);
        end

        function onAddManualParam(app)
            if isempty(app.SourceFile)
                uialert(app.UIFigure, '请先打开一个 .m 文件。', '没有文件', ...
                    'Icon', 'warning');
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

        function summary = runSweep(app, activeIdx, values, overlay, ...
                xName, yNames, parallel, maxScenarios)
            %RUNSWEEP Execute the cartesian product and build reports.
            if nargin < 7
                parallel = false;
            end
            if nargin < 8 || isempty(maxScenarios)
                maxScenarios = 24;
            end
            summary = struct('ok', false, 'sweepRoot', '', 'count', 0, ...
                'report', '', 'overlayPath', '', 'metricsPath', '', ...
                'canceled', false);
            if isempty(app.SourceFile) || isempty(activeIdx)
                return;
            end
            if ~app.confirmInteractiveCalls('批量扫描')
                return;
            end

            app.setBusy(true);
            if strcmp(app.UIFigure.Visible, 'on')
                d = uiprogressdlg(app.UIFigure, 'Title', '批量扫描', ...
                    'Message', '准备...', 'Indeterminate', 'off', ...
                    'Value', 0, 'Cancelable', 'on', ...
                    'CancelText', '取消剩余组');
            else
                d = [];
            end
            oldHV = app.UIFigure.HandleVisibility;
            app.UIFigure.HandleVisibility = 'off';
            cleanupObj = onCleanup(@() app.finishSweep(d, oldHV)); %#ok<NASGU>

            try
                runner = mps.SweepRunner(app.SourceFile, app.Params, ...
                    activeIdx, values, overlay, xName, yNames, ...
                    app.KeepFiguresCheck.Value);
                runner.MaxVariableMB = app.MaxVariableMB;
                runner.MaxTotalMB = app.MaxTotalMB;
                runner.MaxScenarios = maxScenarios;
                runner.Parallel = logical(parallel);
                runner.Progress = @(fraction, message) ...
                    app.updateSweepProgress(d, fraction, message);
                runner.ShouldCancel = @() app.sweepCancelRequested(d);
                out = runner.run();

                app.Results.LastRun = out.agg;
                app.Results.LastWorkspace = out.agg.workspaceData;
                app.Results.OutputDir = out.sweepRoot;
                app.Results.LastReport = out.report;
                app.Results.refreshAll();
                if isempty(out.agg.log)
                    app.LogArea.Value = {''};
                else
                    app.LogArea.Value = splitlines(out.agg.log);
                end
                app.ReportButton.Enable = 'on';
                app.FolderButton.Enable = 'on';
                app.CloseFiguresButton.Enable = 'on';
                app.CompareButton.Enable = 'on';

                summary.ok = true;
                summary.sweepRoot = out.sweepRoot;
                summary.count = out.count;
                summary.report = out.report;
                summary.overlayPath = out.overlayPath;
                summary.metricsPath = out.metricsPath;
                summary.canceled = out.canceled;
                if out.canceled
                    app.StatusLabel.Text = sprintf( ...
                        '批量扫描已取消：已完成 %d 组，报告：%s', ...
                        out.count, out.report);
                elseif isempty(out.metricsPath)
                    app.StatusLabel.Text = sprintf( ...
                        '批量扫描完成：%d 组，%d 张图。报告：%s', ...
                        out.count, numel(out.agg.figures), out.report);
                else
                    app.StatusLabel.Text = sprintf( ...
                        '批量扫描完成：%d 组，%d 张图。指标 CSV：%s', ...
                        out.count, numel(out.agg.figures), out.metricsPath);
                end
            catch err
                app.StatusLabel.Text = ['批量扫描失败：' err.message];
                uialert(app.UIFigure, err.message, '批量扫描失败', ...
                    'Icon', 'error');
            end
            clear cleanupObj;
        end

        function updateSweepProgress(app, d, fraction, message) %#ok<INUSD>
            if ~isempty(d) && isvalid(d)
                d.Value = min(max(fraction, 0), 1);
                d.Message = message;
            end
            drawnow;
        end

        function tf = sweepCancelRequested(~, d)
            tf = false;
            if ~isempty(d) && isvalid(d)
                try
                    tf = logical(d.CancelRequested);
                catch
                end
            end
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

        function finishSweep(app, d, oldHV)
            if ~isempty(d) && isvalid(d)
                delete(d);
            end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                app.UIFigure.HandleVisibility = oldHV;
            end
            app.setBusy(false);
        end

        function onRunHistory(app)
            %ONRUNHISTORY Browse past runs, compare any two, load params.
            if isempty(app.SourceFile)
                uialert(app.UIFigure, '请先打开一个 .m 文件。', '没有文件', ...
                    'Icon', 'warning');
                return;
            end
            root = fullfile(fileparts(app.SourceFile), 'parameter_studio_runs');
            dlg = mps.RunHistoryDialog(root, ...
                'SourceFile', app.SourceFile, ...
                'CurrentOutDir', app.Results.OutputDir);
            uiwait(dlg.UIFigure);
            result = dlg.Result;
            delete(dlg);
            if ~isstruct(result) || ~isfield(result, 'action') || ...
                    ~strcmp(result.action, 'load')
                return;
            end
            app.applyHistoryRun(result);
        end

        function applyHistoryRun(app, result)
            %APPLYHISTORYRUN Load use/newValue/locked from an old run.
            values = result.values;
            if isempty(values)
                uialert(app.UIFigure, '这次运行没有可载入的参数。', ...
                    '无法载入', 'Icon', 'warning');
                return;
            end

            meta = struct();
            if isfield(result, 'meta') && isstruct(result.meta)
                meta = result.meta;
            end
            if isfield(meta, 'sourceFile') && ~isempty(meta.sourceFile) && ...
                    ~strcmpi(meta.sourceFile, app.SourceFile) && ...
                    strcmp(app.UIFigure.Visible, 'on')
                choice = uiconfirm(app.UIFigure, sprintf( ...
                    ['这次运行来自另一个脚本：\n%s\n\n' ...
                     '参数将尽量按名字和行号匹配，是否继续？'], ...
                    meta.sourceFile), '源文件不同', ...
                    'Options', {'继续', '取消'}, ...
                    'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(choice, '继续')
                    return;
                end
            end
            if any([app.Params.isChanged]) && ...
                    strcmp(app.UIFigure.Visible, 'on')
                choice = uiconfirm(app.UIFigure, ...
                    '载入历史参数会覆盖当前的新值，是否继续？', ...
                    '覆盖当前修改', 'Options', {'继续', '取消'}, ...
                    'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(choice, '继续')
                    return;
                end
            end

            preset = struct('name', '历史运行', 'values', values);
            app.pushUndo();
            try
                [app.Params, stats] = mps.applyPreset(app.Params, preset);
            catch err
                uialert(app.UIFigure, err.message, '载入失败', ...
                    'Icon', 'error');
                return;
            end
            app.refreshTable();
            app.StatusLabel.Text = sprintf( ...
                '已从历史运行载入参数：匹配 %d，重名跳过 %d，未匹配 %d。', ...
                stats.matched, stats.ambiguous, stats.unmatched);
            if stats.matched == 0
                uialert(app.UIFigure, sprintf( ...
                    ['没有匹配到参数（未匹配 %d 个）。\n\n' ...
                     '通常是因为脚本改过变量名或行号；历史记录里的 ' ...
                     'name + line 只在原脚本上最准确。'], stats.unmatched), ...
                    '没有匹配', 'Icon', 'warning');
            end
        end

        % -----------------------------------------------------------------
        function onSaveTuned(app)
            if isempty(app.SourceFile)
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
                if app.TableCtl.needsSave()
                    app.saveSession();
                end
            catch
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
                app.UndoButton, app.RedoButton, ...
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
                elseif app.IsFunctionFile
                    app.RunButton.Enable = 'off';
                    app.SweepButton.Enable = 'off';
                    app.ManualButton.Enable = 'off';
                end
                if ~isempty(app.SourceFile)
                    app.PresetSaveButton.Enable = 'on';
                    if isempty(app.Presets)
                        app.PresetLoadButton.Enable = 'off';
                        app.PresetDeleteButton.Enable = 'off';
                    else
                        app.PresetLoadButton.Enable = 'on';
                        app.PresetDeleteButton.Enable = 'on';
                    end
                    if ~app.IsFunctionFile
                        app.SweepButton.Enable = 'on';
                        app.ManualButton.Enable = 'on';
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
                if ~isstruct(app.Results.LastWorkspace) || isempty(fieldnames(app.Results.LastWorkspace))
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
