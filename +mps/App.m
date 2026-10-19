classdef App < handle
%APP The MATLAB Parameter Studio user interface.
%
%   app = mps.App() creates the window.  Most users should call the
%   MatlabParameterStudio launcher instead.

    properties
        UIFigure
        SourceFile = ''
        Params = struct([])
        LastRun = struct()
        LastWorkspace = struct()
        LastReport = ''
        OutputDir = ''
        SourceStamp = struct()
    end

    properties (Access = private)
        FileLabel, StatusLabel
        FilterDrop, SearchField, CountLabel
        Table, SourcePreview
        FigureDrop, FigureImage, FigurePaths
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
        PresetDeleteButton, SweepButton, BulkButton
        UndoButton, RedoButton
        SourceLines = {}
        VisibleIdx = []
        SelectedParams = []
        SelectedVisibleRows = []
        IsFunctionFile = false
        CustomPlotPath = ''
        LastAnnotations = struct([])
        AnnotationFile = ''
        Presets = struct([])
        PresetsFile = ''
        Busy = false
        UndoStack = {}
        RedoStack = {}
        MaxUndo = 50
        RestoringState = false
        SessionDirty = false
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
                if app.SessionDirty
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
            app.UndoStack = {};
            app.RedoStack = {};
            app.SessionDirty = false;
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
            app.LastRun = struct();
            app.LastWorkspace = struct();
            app.LastReport = '';
            app.OutputDir = '';
            app.CustomPlotPath = '';
            app.FigurePaths = {};
            app.SelectedParams = [];
            app.SelectedVisibleRows = [];

            app.FileLabel.Text = filePath;
            app.FileLabel.FontColor = [0.12 0.12 0.12];
            app.FileLabel.Tooltip = filePath;
            app.SourcePreview.Value = {''};
            app.FigureDrop.Items = {'(无图)'};
            app.FigureDrop.Value = '(无图)';
            app.FigureImage.ImageSource = '';
            app.FigureImage.Visible = 'off';
            app.WorkspaceTable.Data = cell(0, 6);
            app.LogArea.Value = {''};
            app.XDrop.Items = {'(无)'};
            app.XDrop.Value = '(无)';
            app.YList.Items = {'(无)'};
            app.YList.Value = {'(无)'};
            cla(app.UIAxes);
            title(app.UIAxes, '运行后在这里绘图');
            app.PlotStatus.Text = '运行脚本后，可选择工作区变量绘图。';

            app.RescanButton.Enable = 'on';
            app.RunButton.Enable = 'on';
            if app.IsFunctionFile
                app.RunButton.Enable = 'off';
            end
            app.SaveButton.Enable = 'on';
            app.ExportButton.Enable = 'on';
            if app.IsFunctionFile
                app.SweepButton.Enable = 'off';
            else
                app.SweepButton.Enable = 'on';
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
            app.updateUndoButtons();
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
            if isnumeric(value) || islogical(value)
                value = num2str(value);
            end
            value = char(value);
            matches = find(strcmp({app.Params.name}, name));
            if isempty(matches)
                return;
            end
            app.pushUndo();
            for k = matches
                if app.Params(k).locked
                    continue;   % locked parameters stay pinned
                end
                app.Params(k).newValue = value;
                app.Params(k).isChanged = ~strcmp(strtrim(app.Params(k).value), ...
                    strtrim(value));
                app.Params(k).use = true;
            end
            app.refreshTable();
        end

        function undoLastEdit(app)
            %UNDOLASTEDIT Restore the table state before the last change.
            app.doUndo();
        end

        function redoLastEdit(app)
            %REDOLASTEDIT Reapply the last undone change.
            app.doRedo();
        end

        function saveSession(app)
            %SAVESESSION Persist unsaved table edits next to the script.
            if isempty(app.SourceFile) || isempty(app.Params)
                return;
            end
            try
                mps.writeSession(app.SourceFile, app.Params, ...
                    app.SourceStamp);
                app.SessionDirty = false;
            catch
            end
        end

        function runCurrent(app)
            %RUNCURRENT Run the current script with the selected parameters.
            app.onRun();
        end

        function plotWorkspace(app, xName, yNames)
            %PLOTWORKSPACE Plot workspace variables in the 绘图 tab.
            if ischar(yNames) || isstring(yNames)
                yNames = cellstr(yNames);
            end
            xName = char(xName);
            if any(strcmp(app.XDrop.Items, xName))
                app.XDrop.Value = xName;
            else
                return;
            end
            yNames = yNames(ismember(yNames, app.YList.Items));
            if isempty(yNames)
                return;
            end
            app.YList.Value = yNames;
            app.onPlot();
        end

        function saveCustomPlot(app)
            %SAVECUSTOMPLOT Save the current 绘图 tab figure and update the report.
            app.onSavePlot();
        end

        function exportCurveCsv(app)
            %EXPORTCURVECSV Write current X/Y selection to curve_data.csv.
            app.onExportCurve();
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
            app.pushUndo();
            for k = 1:numel(app.Params)
                if strcmp(app.Params(k).name, name)
                    app.Params(k).locked = ~app.Params(k).locked;
                    if app.Params(k).locked
                        app.Params(k).newValue = app.Params(k).value;
                        app.Params(k).isChanged = false;
                    end
                end
            end
            app.refreshTable();
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

    methods (Access = private)
        % -----------------------------------------------------------------
        function createUI(app)
            app.UIFigure = uifigure('Name', 'MATLAB Parameter Studio', ...
                'Position', [80 60 1340 840]);
            try
                app.UIFigure.Theme = 'light';   % R2025a+
            catch
            end
            app.UIFigure.CloseRequestFcn = @(s, e) app.onClose();
            app.UIFigure.KeyPressFcn = @(s, e) app.onKeyPress(e);

            root = uigridlayout(app.UIFigure, [3 1]);
            root.RowHeight = {48, '1x', 26};
            root.Padding = [10 10 10 8];
            root.RowSpacing = 8;

            tb = uigridlayout(root, [1 11]);
            tb.Layout.Row = 1;
            tb.ColumnWidth = {108, '1x', 88, 78, 132, 100, 110, 110, 100, 90, 90};
            tb.Padding = [0 0 0 0];
            tb.ColumnSpacing = 6;

            app.OpenButton = uibutton(tb, 'Text', '打开 .m 文件', ...
                'ButtonPushedFcn', @(s, e) app.onOpen());
            app.OpenButton.Layout.Column = 1;

            app.FileLabel = uilabel(tb, 'Text', '未打开文件', ...
                'FontColor', [0.45 0.45 0.45], 'Interpreter', 'none');
            app.FileLabel.Layout.Column = 2;

            app.RescanButton = uibutton(tb, 'Text', '重新扫描', ...
                'Enable', 'off', 'ButtonPushedFcn', @(s, e) app.onRescan());
            app.RescanButton.Layout.Column = 3;

            app.RunButton = uibutton(tb, 'Text', '运行', ...
                'Enable', 'off', 'FontWeight', 'bold', ...
                'BackgroundColor', [0.18 0.45 0.85], ...
                'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(s, e) app.onRun());
            app.RunButton.Layout.Column = 4;

            app.SaveButton = uibutton(tb, 'Text', '保存调参 .m', ...
                'Enable', 'off', 'ButtonPushedFcn', @(s, e) app.onSaveTuned());
            app.SaveButton.Layout.Column = 5;

            app.ReportButton = uibutton(tb, 'Text', '打开报告', ...
                'Enable', 'off', 'ButtonPushedFcn', @(s, e) app.onOpenReport());
            app.ReportButton.Layout.Column = 6;

            app.FolderButton = uibutton(tb, 'Text', '打开结果文件夹', ...
                'Enable', 'off', 'ButtonPushedFcn', @(s, e) app.onOpenFolder());
            app.FolderButton.Layout.Column = 7;

            app.ExportButton = uibutton(tb, 'Text', '导出参数 JSON', ...
                'Enable', 'off', 'ButtonPushedFcn', @(s, e) app.onExportParams());
            app.ExportButton.Layout.Column = 8;

            app.CloseFiguresButton = uibutton(tb, 'Text', '关闭结果图窗', ...
                'Enable', 'off', 'ButtonPushedFcn', @(s, e) app.onCloseFigures());
            app.CloseFiguresButton.Layout.Column = 9;

            app.CompareButton = uibutton(tb, 'Text', '运行历史', ...
                'Enable', 'off', 'ButtonPushedFcn', @(s, e) app.onRunHistory());
            app.CompareButton.Layout.Column = 10;

            app.HelpButton = uibutton(tb, 'Text', '快速上手', ...
                'ButtonPushedFcn', @(s, e) app.onHelp());
            app.HelpButton.Layout.Column = 11;

            main = uigridlayout(root, [1 2]);
            main.Layout.Row = 2;
            main.ColumnWidth = {'1x', '0.72x'};
            main.Padding = [0 0 0 0];
            main.ColumnSpacing = 8;

            lp = uipanel(main, 'Title', '参数', 'FontWeight', 'bold');
            lp.Layout.Column = 1;
            lg = uigridlayout(lp, [5 1]);
            lg.RowHeight = {34, 30, 30, '1x', 96};
            lg.Padding = [8 8 8 8];
            lg.RowSpacing = 6;

            fg = uigridlayout(lg, [1 6]);
            fg.Layout.Row = 1;
            fg.ColumnWidth = {120, '1x', 150, 92, 92, 104};
            fg.Padding = [0 0 0 0];
            fg.ColumnSpacing = 6;

            app.FilterDrop = uidropdown(fg, ...
                'Items', {'推荐参数', '全部数字', '已修改'}, ...
                'Value', '推荐参数', ...
                'ValueChangedFcn', @(s, e) app.refreshTable());
            app.FilterDrop.Layout.Column = 1;

            app.SearchField = uieditfield(fg, 'text', ...
                'Placeholder', '搜索参数名/说明/行号', ...
                'ValueChangedFcn', @(s, e) app.refreshTable());
            app.SearchField.Layout.Column = 2;

            app.CountLabel = uilabel(fg, 'Text', '0 / 0', ...
                'HorizontalAlignment', 'right', ...
                'FontColor', [0.4 0.4 0.4]);
            app.CountLabel.Layout.Column = 3;

            app.SelectAllButton = uibutton(fg, 'Text', '全选推荐', ...
                'ButtonPushedFcn', @(s, e) app.onSelectAll());
            app.SelectAllButton.Layout.Column = 4;

            app.ResetButton = uibutton(fg, 'Text', '重置新值', ...
                'ButtonPushedFcn', @(s, e) app.onReset());
            app.ResetButton.Layout.Column = 5;

            app.BulkButton = uibutton(fg, 'Text', '批量修改...', ...
                'Enable', 'off', ...
                'ButtonPushedFcn', @(s, e) app.onBulkEdit());
            app.BulkButton.Layout.Column = 6;

            ag = uigridlayout(lg, [1 6]);
            ag.Layout.Row = 2;
            ag.ColumnWidth = {130, '1x', 96, 96, 96, 130};
            ag.Padding = [0 0 0 0];
            ag.ColumnSpacing = 6;

            app.AnnotateTemplateButton = uibutton(ag, ...
                'Text', '生成注释 JSON', 'Enable', 'off', ...
                'ButtonPushedFcn', @(s, e) app.onWriteAnnotationTemplate());
            app.AnnotateTemplateButton.Layout.Column = 1;

            app.AnnotationStatus = uilabel(ag, 'Text', '未导入注释', ...
                'FontColor', [0.4 0.4 0.4]);
            app.AnnotationStatus.Layout.Column = 2;

            app.ImportAnnotationButton = uibutton(ag, ...
                'Text', '导入注释', 'Enable', 'off', ...
                'ButtonPushedFcn', @(s, e) app.onImportAnnotations());
            app.ImportAnnotationButton.Layout.Column = 3;

            app.ClearAnnotationButton = uibutton(ag, ...
                'Text', '清空注释', 'Enable', 'off', ...
                'ButtonPushedFcn', @(s, e) app.onClearAnnotations());
            app.ClearAnnotationButton.Layout.Column = 4;

            app.LockButton = uibutton(ag, ...
                'Text', '锁定选中', 'Enable', 'off', ...
                'ButtonPushedFcn', @(s, e) app.onToggleLock());
            app.LockButton.Layout.Column = 5;

            app.KeepFiguresCheck = uicheckbox(ag, ...
                'Text', '保留结果图窗', 'Value', false);
            app.KeepFiguresCheck.Layout.Column = 6;

            pg2 = uigridlayout(lg, [1 6]);
            pg2.Layout.Row = 3;
            pg2.ColumnWidth = {150, '1x', 96, 72, 72, 100};
            pg2.Padding = [0 0 0 0];
            pg2.ColumnSpacing = 6;

            app.PresetDrop = uidropdown(pg2, 'Items', {'(无参数集)'}, ...
                'Value', '(无参数集)');
            app.PresetDrop.Layout.Column = 1;

            app.PresetNameField = uieditfield(pg2, 'text', ...
                'Placeholder', '新参数集名称，如 基线 / 高刚度');
            app.PresetNameField.Layout.Column = 2;

            app.PresetSaveButton = uibutton(pg2, 'Text', '保存为参数集', ...
                'Enable', 'off', ...
                'ButtonPushedFcn', @(s, e) app.onSavePreset());
            app.PresetSaveButton.Layout.Column = 3;

            app.PresetLoadButton = uibutton(pg2, 'Text', '载入', ...
                'Enable', 'off', ...
                'ButtonPushedFcn', @(s, e) app.onLoadPreset());
            app.PresetLoadButton.Layout.Column = 4;

            app.PresetDeleteButton = uibutton(pg2, 'Text', '删除', ...
                'Enable', 'off', ...
                'ButtonPushedFcn', @(s, e) app.onDeletePreset());
            app.PresetDeleteButton.Layout.Column = 5;

            app.SweepButton = uibutton(pg2, 'Text', '批量扫描...', ...
                'Enable', 'off', ...
                'ButtonPushedFcn', @(s, e) app.onOpenSweep());
            app.SweepButton.Layout.Column = 6;

            app.Table = uitable(lg, ...
                'ColumnName', {'使用', '锁定', '参数', '当前值', '新值', '行', '类型', '说明', '注释'}, ...
                'ColumnEditable', [true true false false true false false false false], ...
                'ColumnFormat', {'logical', 'logical', 'char', 'char', 'char', 'numeric', 'char', 'char', 'char'}, ...
                'ColumnWidth', {40, 46, 160, 70, 70, 34, 68, 110, '1x'}, ...
                'RowName', [], ...
                'CellEditCallback', @(s, e) app.onCellEdit(s, e), ...
                'CellSelectionCallback', @(s, e) app.onCellSelect(s, e));
            app.Table.Layout.Row = 4;
            try
                app.Table.Multiselect = 'on';   % R2023b+
            catch
            end
            try
                app.Table.Tooltip = ...
                    '双击“参数”或“行”列，在 MATLAB 编辑器中打开对应行';
                app.Table.DoubleClickedFcn = @(s, e) app.onOpenInEditor(e);
            catch
            end

            sourceGrid = uigridlayout(lg, [1 3]);
            sourceGrid.Layout.Row = 5;
            sourceGrid.ColumnWidth = {'1x', 64, 64};
            sourceGrid.Padding = [0 0 0 0];
            sourceGrid.ColumnSpacing = 6;
            app.SourcePreview = uitextarea(sourceGrid, 'Editable', 'off', ...
                'FontName', 'Consolas', 'FontSize', 11, 'Value', {''});
            app.UndoButton = uibutton(sourceGrid, 'Text', '撤销', ...
                'Enable', 'off', 'ButtonPushedFcn', @(s, e) app.undoLastEdit());
            app.UndoButton.Layout.Column = 2;
            app.RedoButton = uibutton(sourceGrid, 'Text', '重做', ...
                'Enable', 'off', 'ButtonPushedFcn', @(s, e) app.redoLastEdit());
            app.RedoButton.Layout.Column = 3;

            tg = uitabgroup(main);
            tg.Layout.Column = 2;

            t1 = uitab(tg, 'Title', '结果图');
            rg = uigridlayout(t1, [2 2]);
            rg.RowHeight = {32, '1x'};
            rg.ColumnWidth = {'1x', 110};
            rg.Padding = [8 8 8 8];
            rg.RowSpacing = 6;

            app.FigureDrop = uidropdown(rg, 'Items', {'(无图)'}, ...
                'Value', '(无图)', ...
                'ValueChangedFcn', @(s, e) app.showFigure());
            app.FigureDrop.Layout.Row = 1;
            app.FigureDrop.Layout.Column = 1;

            app.OpenReportInline = uibutton(rg, 'Text', '浏览器打开', ...
                'ButtonPushedFcn', @(s, e) app.onOpenReport());
            app.OpenReportInline.Layout.Row = 1;
            app.OpenReportInline.Layout.Column = 2;

            app.FigureImage = uiimage(rg, 'ScaleMethod', 'fit', 'Visible', 'off');
            app.FigureImage.Layout.Row = 2;
            app.FigureImage.Layout.Column = [1 2];

            t2 = uitab(tg, 'Title', '工作区');
            wg = uigridlayout(t2, [1 1]);
            wg.Padding = [8 8 8 8];
            app.WorkspaceTable = uitable(wg, ...
                'ColumnName', {'变量', '类型', '大小', '最小值', '最大值', '预览'}, ...
                'ColumnWidth', {100, 80, 75, 75, 75, '1x'}, ...
                'ColumnEditable', false, 'RowName', []);

            t3 = uitab(tg, 'Title', '绘图');
            pg = uigridlayout(t3, [5 3]);
            pg.RowHeight = {30, 82, 32, 22, '1x'};
            pg.ColumnWidth = {72, '1x', '1x'};
            pg.Padding = [8 8 8 8];
            pg.RowSpacing = 6;

            uilabel(pg, 'Text', 'X 轴');
            app.XDrop = uidropdown(pg, 'Items', {'(无)'}, 'Value', '(无)');
            app.XDrop.Layout.Row = 1;
            app.XDrop.Layout.Column = [2 3];

            uilabel(pg, 'Text', 'Y 轴（可多选）');
            app.YList = uilistbox(pg, 'Items', {'(无)'}, 'Value', {'(无)'}, ...
                'Multiselect', 'on');
            app.YList.Layout.Row = 2;
            app.YList.Layout.Column = [2 3];

            app.PlotButton = uibutton(pg, 'Text', '绘制', ...
                'Enable', 'off', 'ButtonPushedFcn', @(s, e) app.onPlot());
            app.PlotButton.Layout.Row = 3;
            app.PlotButton.Layout.Column = 1;

            app.SavePlotButton = uibutton(pg, 'Text', '保存图并更新报告', ...
                'Enable', 'off', 'ButtonPushedFcn', @(s, e) app.onSavePlot());
            app.SavePlotButton.Layout.Row = 3;
            app.SavePlotButton.Layout.Column = 2;

            app.ExportCsvButton = uibutton(pg, 'Text', '导出曲线 CSV', ...
                'Enable', 'off', 'ButtonPushedFcn', @(s, e) app.onExportCurve());
            app.ExportCsvButton.Layout.Row = 3;
            app.ExportCsvButton.Layout.Column = 3;

            app.PlotStatus = uilabel(pg, 'Text', '运行脚本后，可选择工作区变量绘图。', ...
                'FontColor', [0.4 0.4 0.4]);
            app.PlotStatus.Layout.Row = 4;
            app.PlotStatus.Layout.Column = [1 3];

            app.UIAxes = uiaxes(pg);
            app.UIAxes.Layout.Row = 5;
            app.UIAxes.Layout.Column = [1 3];
            app.UIAxes.XGrid = 'on';
            app.UIAxes.YGrid = 'on';
            app.UIAxes.Box = 'on';
            app.UIAxes.FontSize = 10;
            title(app.UIAxes, '运行后在这里绘图');

            t4 = uitab(tg, 'Title', '日志');
            lg2 = uigridlayout(t4, [1 1]);
            lg2.Padding = [8 8 8 8];
            app.LogArea = uitextarea(lg2, 'Editable', 'off', ...
                'FontName', 'Consolas', 'FontSize', 11, 'Value', {''});

            app.StatusLabel = uilabel(root, ...
                'Text', '就绪。第 1 步：点左上角“打开 .m 文件”。', ...
                'FontColor', [0.35 0.35 0.35]);
            app.StatusLabel.Layout.Row = 3;

            app.setTooltips();
        end

        % -----------------------------------------------------------------
        function setTooltips(app)
            %SETTOOLTIPS One-sentence Chinese hints for every control.
            set(app.OpenButton, 'Tooltip', '打开一个 .m 脚本开始调参');
            set(app.RescanButton, 'Tooltip', ...
                '重新扫描当前文件；会丢弃还没运行的新值');
            set(app.RunButton, 'Tooltip', ...
                '用勾选/改好的参数运行脚本（快捷键 F5 或 Ctrl+Enter）');
            set(app.SaveButton, 'Tooltip', ...
                '另存为 <原名>_tuned.m，可以脱离本工具直接在 MATLAB 里运行');
            set(app.ReportButton, 'Tooltip', ...
                '用浏览器打开本次运行的 HTML 报告（参数+图+变量+日志）');
            set(app.FolderButton, 'Tooltip', ...
                '打开结果文件夹，里面有图、workspace.mat 和报告');
            set(app.ExportButton, 'Tooltip', ...
                '把当前识别出的所有参数导出成 JSON 文件');
            set(app.CloseFiguresButton, 'Tooltip', ...
                '关掉本次运行留在屏幕上的图窗');
            set(app.CompareButton, 'Tooltip', ...
                '查看历史运行，任意两次做对比，或载入某次的参数');
            set(app.BulkButton, 'Tooltip', ...
                '对多选行批量设值、乘系数、勾选、锁定，或从 Excel 粘贴一列');
            set(app.HelpButton, 'Tooltip', '30 秒看懂：从打开文件到保存结果');

            set(app.FilterDrop, 'Tooltip', ...
                '选择显示哪些参数：推荐参数 / 全部数字 / 已修改');
            set(app.SearchField, 'Tooltip', '按参数名、注释或行号搜索');
            set(app.SelectAllButton, 'Tooltip', ...
                '一键勾选或取消所有推荐参数');
            set(app.ResetButton, 'Tooltip', ...
                '把所有“新值”恢复成脚本里的当前值');
            set(app.AnnotateTemplateButton, 'Tooltip', ...
                '生成注释模板 JSON，交给 AI 填写参数含义和单位');
            set(app.ImportAnnotationButton, 'Tooltip', ...
                '导入 AI 填好的注释 JSON，“注释”列会显示中文含义');
            set(app.ClearAnnotationButton, 'Tooltip', ...
                '清除当前表格里的注释（注释文件不会被删除）');
            set(app.LockButton, 'Tooltip', ...
                '把选中行的参数钉死在原值，运行和保存都不会改它');
            set(app.UndoButton, 'Tooltip', '撤销上一次参数修改（Ctrl+Z）');
            set(app.RedoButton, 'Tooltip', '重做刚撤销的修改（Ctrl+Y）');
            set(app.KeepFiguresCheck, 'Tooltip', ...
                '勾选：运行结束后保留图窗；不勾选：图窗自动关闭（推荐）');
            set(app.PresetDrop, 'Tooltip', '已保存的参数方案');
            set(app.PresetNameField, 'Tooltip', ...
                '给当前方案起个名字，例如 基线 / 高刚度 / 低阻尼');
            set(app.PresetSaveButton, 'Tooltip', ...
                '把当前的勾选、新值、锁定状态存成一个命名方案');
            set(app.PresetLoadButton, 'Tooltip', ...
                '把选中方案的新值、勾选、锁定恢复到表格');
            set(app.PresetDeleteButton, 'Tooltip', '删除选中的参数方案');
            set(app.SweepButton, 'Tooltip', ...
                '多个参数一次跑多组值，自动出叠加曲线和扫描报告');

            set(app.FigureDrop, 'Tooltip', '选择要预览的输出图');
            set(app.OpenReportInline, 'Tooltip', '用浏览器打开 HTML 报告');
            set(app.XDrop, 'Tooltip', '绘图时的 X 轴变量');
            set(app.YList, 'Tooltip', '绘图时的 Y 轴变量，可以多选');
            set(app.PlotButton, 'Tooltip', '按选择的 X/Y 变量画图');
            set(app.SavePlotButton, 'Tooltip', ...
                '保存这张图，并把报告更新为包含它');
            set(app.ExportCsvButton, 'Tooltip', ...
                '把当前 X/Y 曲线导出成 curve_data.csv（Excel 可直接打开）');
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
            app.SessionDirty = true;
            app.refreshTable();
            app.StatusLabel.Text = sprintf( ...
                '已重新扫描并保留修改：匹配 %d，重名跳过 %d，未匹配 %d。', ...
                stats.matched, stats.ambiguous, stats.unmatched);
        end

        function onHelp(app)
            %ONHELP Show a short, plain-language quick start.
            fig = uifigure('Name', '快速上手', 'Position', [320 180 640 480]);
            g = uigridlayout(fig, [2 1]);
            g.RowHeight = {'1x', 34};
            g.Padding = [14 14 14 14];
            g.RowSpacing = 10;
            txt = { ...
                '30 秒上手', ...
                '', ...
                '1. 点“打开 .m 文件”，选一个 MATLAB 脚本。', ...
                '2. 左侧表格列出能改的参数：在“新值”列输入新的数字。', ...
                '    “使用”打勾 = 本次运行用这个新值；', ...
                '    “锁定”打勾 = 这个参数不许改，永远保持原值。', ...
                '3. 点“运行”（快捷键 F5）。', ...
                '4. 看结果：', ...
                '    · “结果图”看脚本产生的图；', ...
                '    · “工作区”看变量；“绘图”里可自己选 X/Y 出图、导出 CSV；', ...
                '    · “打开报告”看 HTML 报告（参数变化 + 图 + 变量 + 日志）。', ...
                '5. 满意后点“保存调参 .m”，得到可以直接运行的脚本。', ...
                '', ...
                '常用进阶（不清楚可以先不用）：', ...
                '· 批量改参数：Ctrl/Shift 多选行 → 点“批量修改...”或按 Ctrl+B。', ...
                '· 改错了：Ctrl+Z 撤销，Ctrl+Y 重做（表格下方也有按钮）。', ...
                '· 双击参数行：在 MATLAB 编辑器中打开对应源码位置。', ...
                '· 关闭应用后重新打开同一脚本，会恢复上次未运行的修改。', ...
                '· 保存调参 .m 前会先显示 diff，确认后才写文件。', ...
                '· 看不懂参数含义：生成注释 JSON → 给 AI 填写 → 导入注释。', ...
                '· 想存几套方案：在“参数集”输入名字 → 保存为参数集。', ...
                '· 想对比两次：点“运行历史”，任选两次设为 A/B 后对比。', ...
                '· 想批量试值：点“批量扫描...”，填 1,2,4 或 1:0.5:5。', ...
                '', ...
                '提示：运行脚本时图窗默认不弹出，不会打扰你；', ...
                '想看就勾“保留结果图窗”。'};
            ta = uitextarea(g, 'Editable', 'off', 'FontSize', 12, 'Value', txt);
            ta.Layout.Row = 1;
            b = uibutton(g, 'Text', '知道了', ...
                'ButtonPushedFcn', @(s, e) delete(fig));
            b.Layout.Row = 2;
            uiwait(fig);
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
                params = app.Params;
                for k = 1:numel(params)
                    if params(k).use
                        [ok, ~] = mps.validateValue(params(k).newValue);
                        if ~ok
                            error('参数 %s 的新值无效：%s', ...
                                params(k).name, params(k).newValue);
                        end
                    end
                end

                % Close figures from the previous run so they do not pile up.
                if isfield(app.LastRun, 'figureHandles')
                    old = app.LastRun.figureHandles;
                    for k = 1:numel(old)
                        if isvalid(old(k))
                            close(old(k));
                        end
                    end
                end

                outDir = app.makeOutputDir();
                app.OutputDir = outDir;

                % run() changes the current folder to the script's folder,
                % so the generated copy must live next to the original file
                % for relative paths (data files, images, ...) to work.
                keepScript = fullfile(outDir, 'run_script.m');
                runDir = fileparts(app.SourceFile);
                tempScript = fullfile(runDir, ...
                    sprintf('mps_run_%s.m', datestr(now, 'yyyymmdd_HHMMSSFFF')));
                try
                    mps.applyEdits(app.SourceFile, params, tempScript, ...
                        'NeutralizeCloseAll', true);
                catch
                    tempScript = keepScript;
                    mps.applyEdits(app.SourceFile, params, tempScript, ...
                        'NeutralizeCloseAll', true);
                end
                scriptCleaner = onCleanup(@() app.cleanupTempScript(tempScript, keepScript)); %#ok<NASGU>

                setProgress(d, '运行 MATLAB 脚本...');

                % Create the script's figures invisibly, capture them, and
                % only show them again if the user asked to keep them.
                oldFigVis = get(groot, 'defaultFigureVisible');
                set(groot, 'defaultFigureVisible', 'off');
                figVisCleaner = onCleanup(@() set(groot, ...
                    'defaultFigureVisible', oldFigVis)); %#ok<NASGU>
                r = mps.runScript(app.SourceFile, tempScript, outDir);
                clear figVisCleaner;
                if app.KeepFiguresCheck.Value
                    for fk = 1:numel(r.figureHandles)
                        if isvalid(r.figureHandles(fk))
                            set(r.figureHandles(fk), 'Visible', 'on');
                        end
                    end
                else
                    for fk = 1:numel(r.figureHandles)
                        if isvalid(r.figureHandles(fk))
                            delete(r.figureHandles(fk));
                        end
                    end
                    r.figureHandles = gobjects(0);
                end

                try
                    if ~isfile(keepScript) && ~strcmpi(tempScript, keepScript)
                        copyfile(tempScript, keepScript);
                    end
                    if isfile(keepScript)
                        r.scriptPath = keepScript;
                    end
                catch
                end
                clear scriptCleaner;
                app.LastRun = r;
                app.LastWorkspace = r.workspaceData;

                setProgress(d, '生成 HTML 报告...');
                app.LastReport = mps.writeReport(outDir, app.SourceFile, params, r);

                app.refreshResults();
                app.refreshWorkspace();
                app.refreshPlotVariables();
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
                        sum([params.use]), numel(r.figures), ...
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

        function outDir = makeOutputDir(app)
            stamp = datestr(now, 'yyyymmdd_HHMMSS');
            base = fileparts(app.SourceFile);
            root = fullfile(base, 'parameter_studio_runs');
            try
                if ~isfolder(root)
                    mkdir(root);
                end
                outDir = fullfile(root, stamp);
                n = 2;
                while isfolder(outDir)
                    outDir = fullfile(root, sprintf('%s_%d', stamp, n));
                    n = n + 1;
                end
                mkdir(outDir);
            catch
                root = fullfile(tempdir, 'matlab_parameter_studio_runs');
                if ~isfolder(root)
                    mkdir(root);
                end
                outDir = fullfile(root, stamp);
                if isfolder(outDir)
                    outDir = fullfile(root, [stamp '_' num2str(randi(9999))]);
                end
                mkdir(outDir);
            end
        end

        function cleanupTempScript(app, tempScript, keepScript)
            %CLEANUPTEMPSCRIPT Keep a copy of the generated script, remove temp.
            if ~strcmpi(tempScript, keepScript) && isfile(tempScript) && ...
                    ~isfile(keepScript)
                try
                    copyfile(tempScript, keepScript);
                catch
                end
            end
            if ~strcmpi(tempScript, keepScript) && isfile(tempScript)
                try
                    delete(tempScript);
                catch
                end
            end
        end

        % -----------------------------------------------------------------
        function pushUndo(app)
            %PUSHUNDO Snapshot the table before a user-visible change.
            if app.RestoringState
                return;
            end
            app.UndoStack{end+1} = app.snapshotState();
            if numel(app.UndoStack) > app.MaxUndo
                app.UndoStack(1) = [];
            end
            app.RedoStack = {};
            app.SessionDirty = true;
            app.updateUndoButtons();
        end

        function state = snapshotState(app)
            state = {app.Params, app.SelectedParams, ...
                app.LastAnnotations, app.AnnotationFile};
        end

        function restoreState(app, state)
            app.Params = state{1};
            app.SelectedParams = state{2};
            app.LastAnnotations = state{3};
            app.AnnotationFile = state{4};
        end

        function doUndo(app)
            if isempty(app.UndoStack)
                return;
            end
            app.RedoStack{end+1} = app.snapshotState();
            state = app.UndoStack{end};
            app.UndoStack(end) = [];
            app.RestoringState = true;
            app.restoreState(state);
            app.RestoringState = false;
            app.SessionDirty = true;
            app.refreshTable();
            app.StatusLabel.Text = '已撤销上一次修改。';
            app.updateUndoButtons();
        end

        function doRedo(app)
            if isempty(app.RedoStack)
                return;
            end
            app.UndoStack{end+1} = app.snapshotState();
            state = app.RedoStack{end};
            app.RedoStack(end) = [];
            app.RestoringState = true;
            app.restoreState(state);
            app.RestoringState = false;
            app.SessionDirty = true;
            app.refreshTable();
            app.StatusLabel.Text = '已重做上一次修改。';
            app.updateUndoButtons();
        end

        function updateUndoButtons(app)
            if isempty(app.UndoButton) || ~isvalid(app.UndoButton)
                return;
            end
            if app.Busy
                app.UndoButton.Enable = 'off';
                app.RedoButton.Enable = 'off';
                return;
            end
            if isempty(app.UndoStack)
                app.UndoButton.Enable = 'off';
            else
                app.UndoButton.Enable = 'on';
            end
            if isempty(app.RedoStack)
                app.RedoButton.Enable = 'off';
            else
                app.RedoButton.Enable = 'on';
            end
        end

        % -----------------------------------------------------------------
        function refreshTable(app)
            if isempty(app.Params)
                app.Table.Data = cell(0, 9);
                app.VisibleIdx = [];
                app.SelectedParams = [];
                app.SelectedVisibleRows = [];
                app.CountLabel.Text = '0 / 0';
                app.updateAnnotationStatus();
                app.updateUndoButtons();
                return;
            end

            for k = 1:numel(app.Params)
                app.Params(k).isChanged = ~strcmp( ...
                    strtrim(app.Params(k).value), ...
                    strtrim(app.Params(k).newValue));
            end

            mode = app.FilterDrop.Value;
            q = lower(strtrim(char(app.SearchField.Value)));
            idx = [];
            for k = 1:numel(app.Params)
                p = app.Params(k);
                switch mode
                    case '推荐参数'
                        keep = p.score >= 3;
                    case '已修改'
                        keep = p.isChanged;
                    otherwise
                        keep = true;
                end
                if keep && ~isempty(q)
                    hay = lower(sprintf('%s %s %s %s %s %d', ...
                        p.name, p.description, p.unit, p.note, p.context, p.line));
                    keep = contains(hay, q);
                end
                if keep
                    idx(end+1) = k; %#ok<AGROW>
                end
            end
            app.VisibleIdx = idx;

            data = cell(numel(idx), 9);
            for j = 1:numel(idx)
                p = app.Params(idx(j));
                note = p.note;
                if isempty(note)
                    note = p.context;
                end
                if numel(note) > 120
                    note = [note(1:117), '...'];
                end
                if p.locked
                    nameCell = ['[锁] ' p.name];
                else
                    nameCell = p.name;
                end
                data{j,1} = p.use;
                data{j,2} = p.locked;
                data{j,3} = nameCell;
                data{j,4} = p.value;
                data{j,5} = p.newValue;
                data{j,6} = p.line;
                data{j,7} = categoryLabel(p.category);
                data{j,8} = note;
                data{j,9} = annotationText(p);
            end
            app.Table.Data = data;
            app.restoreTableSelection();
            app.CountLabel.Text = sprintf('%d / %d · 已修改 %d', ...
                numel(idx), numel(app.Params), sum([app.Params.isChanged]));
            app.updateAnnotationStatus();

            rec = [app.Params.score] >= 3;
            if any(rec)
                if all([app.Params(rec).use])
                    app.SelectAllButton.Text = '取消全选';
                else
                    app.SelectAllButton.Text = '全选推荐';
                end
            end
            app.updateUndoButtons();
            if app.SessionDirty
                app.saveSession();
            end
        end

        function onCellEdit(app, ~, event)
            if isempty(event.Indices) || isempty(app.VisibleIdx)
                return;
            end
            row = event.Indices(1);
            col = event.Indices(2);
            if row < 1 || row > numel(app.VisibleIdx)
                return;
            end
            idx = app.VisibleIdx(row);
            if col == 1
                app.pushUndo();
                app.Params(idx).use = logical(event.NewData);
            elseif col == 2
                app.pushUndo();
                lock = logical(event.NewData);
                app.Params(idx).locked = lock;
                if lock
                    % Locking pins the original value immediately.
                    app.Params(idx).newValue = app.Params(idx).value;
                    app.Params(idx).isChanged = false;
                end
            elseif col == 5
                if app.Params(idx).locked
                    uialert(app.UIFigure, ...
                        '该参数已锁定，不能修改。请先在“锁定”列取消勾选。', ...
                        '参数已锁定', 'Icon', 'warning');
                    app.refreshTable();
                    return;
                end
                newVal = strtrim(char(event.NewData));
                if isempty(newVal)
                    newVal = app.Params(idx).value;
                end
                [ok, ~] = mps.validateValue(newVal);
                if ~ok
                    uialert(app.UIFigure, ...
                        sprintf('“%s”不是有效的数值表达式。\n\n示例：2、2*pi、[1 2 3]、1:0.1:10', ...
                        newVal), '输入无效', 'Icon', 'warning');
                    app.refreshTable();
                    return;
                end
                app.pushUndo();
                app.Params(idx).newValue = newVal;
                app.Params(idx).isChanged = ~strcmp( ...
                    strtrim(app.Params(idx).value), newVal);
            end
            app.refreshTable();
        end

        function restoreTableSelection(app)
            %RESTORETABLESELECTION Keep selected parameters across refreshes.
            if ~isempty(app.SelectedParams)
                [keep, visibleRows] = ismember(app.SelectedParams, ...
                    app.VisibleIdx);
                app.SelectedParams = app.SelectedParams(keep);
                visibleRows = visibleRows(keep);
            else
                visibleRows = [];
            end
            app.SelectedVisibleRows = visibleRows(:)';
            try
                if isempty(visibleRows)
                    app.Table.Selection = [];
                else
                    app.Table.Selection = [visibleRows(:), ...
                        ones(numel(visibleRows), 1)];
                end
            catch
            end
            app.updateLockButton();
        end

        function onCellSelect(app, ~, event)
            if isempty(event.Indices) || isempty(app.VisibleIdx)
                app.SelectedParams = [];
                app.SelectedVisibleRows = [];
                app.SourcePreview.Value = {''};
                app.updateLockButton();
                return;
            end
            rows = [];
            try
                selection = app.Table.Selection;
                if ~isempty(selection)
                    rows = unique(selection(:, 1));
                end
            catch
            end
            if isempty(rows)
                rows = unique(event.Indices(:, 1));
            end
            rows = rows(rows >= 1 & rows <= numel(app.VisibleIdx));
            if isempty(rows)
                app.SelectedParams = [];
                app.SelectedVisibleRows = [];
                app.SourcePreview.Value = {''};
                app.updateLockButton();
                return;
            end
            app.SelectedVisibleRows = rows(:)';
            app.SelectedParams = app.VisibleIdx(rows);
            app.updateLockButton();

            row = rows(end);
            idx = app.VisibleIdx(row);
            if isempty(app.SourceLines)
                app.SourcePreview.Value = {''};
                return;
            end
            lineNo = app.Params(idx).line;
            lo = max(1, lineNo - 2);
            hi = min(numel(app.SourceLines), lineNo + 2);
            preview = cell(hi - lo + 1, 1);
            for j = lo:hi
                if j == lineNo
                    marker = '>> ';
                else
                    marker = '   ';
                end
                preview{j - lo + 1} = sprintf('%s%4d | %s', ...
                    marker, j, app.SourceLines{j});
            end
            ann = annotationText(app.Params(idx));
            if ~isempty(ann)
                preview = [{'注释：' ann}; {''}; preview];
            end
            app.SourcePreview.Value = preview;
        end

        function onSelectAll(app)
            if isempty(app.Params)
                return;
            end
            rec = [app.Params.score] >= 3;
            if ~any(rec)
                return;
            end
            app.pushUndo();
            if all([app.Params(rec).use])
                for k = find(rec)
                    app.Params(k).use = false;
                end
            else
                for k = find(rec)
                    app.Params(k).use = true;
                end
            end
            app.refreshTable();
        end

        function onReset(app)
            app.pushUndo();
            for k = 1:numel(app.Params)
                app.Params(k).newValue = app.Params(k).value;
                app.Params(k).isChanged = false;
            end
            app.refreshTable();
            app.StatusLabel.Text = '已把所有新值重置为当前值。';
        end

        function onBulkEdit(app)
            %ONBULKEDIT Batch operations for the multi-selected rows.
            if isempty(app.SourceFile)
                uialert(app.UIFigure, '请先打开一个 .m 文件。', '没有文件', ...
                    'Icon', 'warning');
                return;
            end
            if isempty(app.Params)
                return;
            end
            dlg = mps.BulkEditDialog(app.Params, app.SelectedParams, ...
                app.VisibleIdx);
            uiwait(dlg.UIFigure);
            result = dlg.Result;
            delete(dlg);
            if ~isstruct(result) || ~isfield(result, 'op')
                return;   % cancelled
            end

            app.pushUndo();
            try
                if strcmp(result.op, 'paste')
                    [app.Params, stats] = mps.applyPastedValues( ...
                        app.Params, result.indices, result.values);
                else
                    [app.Params, stats] = mps.bulkEdit( ...
                        app.Params, result.indices, result.op, result.value);
                end
            catch err
                uialert(app.UIFigure, err.message, '批量修改失败', ...
                    'Icon', 'error');
                return;
            end

            app.refreshTable();
            msg = sprintf('批量修改：%d 个参数已更新', stats.changed);
            if stats.skippedLocked > 0
                msg = sprintf('%s，跳过已锁定 %d 个', msg, stats.skippedLocked);
            end
            if stats.skippedNonNumeric > 0
                msg = sprintf('%s，跳过非数值 %d 个', msg, ...
                    stats.skippedNonNumeric);
            end
            if stats.skippedInvalid > 0
                msg = sprintf('%s，跳过无效 %d 个', msg, stats.skippedInvalid);
            end
            app.StatusLabel.Text = [msg '。'];
        end

        % -----------------------------------------------------------------
        function updateAnnotationStatus(app)
            total = numel(app.Params);
            n = 0;
            for k = 1:total
                if ~isempty(app.Params(k).description) || ...
                        ~isempty(app.Params(k).unit)
                    n = n + 1;
                end
            end
            if n == 0
                app.AnnotationStatus.Text = '未导入注释';
                app.AnnotationStatus.FontColor = [0.4 0.4 0.4];
            else
                app.AnnotationStatus.Text = sprintf('已注释 %d / %d', n, total);
                app.AnnotationStatus.FontColor = [0.05 0.45 0.15];
            end
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

        function updateLockButton(app)
            indices = app.SelectedParams;
            if isempty(indices)
                app.LockButton.Text = '锁定选中';
                return;
            end
            if all([app.Params(indices).locked])
                app.LockButton.Text = sprintf('解锁选中 (%d)', numel(indices));
            else
                app.LockButton.Text = sprintf('锁定选中 (%d)', numel(indices));
            end
        end

        function onToggleLock(app)
            indices = app.SelectedParams;
            if isempty(indices)
                uialert(app.UIFigure, '请先在参数表里点选一行（可多选）。', ...
                    '没有选中行', 'Icon', 'warning');
                return;
            end
            app.pushUndo();
            if all([app.Params(indices).locked])
                for idx = indices
                    app.Params(idx).locked = false;
                    app.Params(idx).isChanged = ~strcmp( ...
                        strtrim(app.Params(idx).value), ...
                        strtrim(app.Params(idx).newValue));
                end
                app.StatusLabel.Text = sprintf('已解锁 %d 个参数。', ...
                    numel(indices));
            else
                for idx = indices
                    app.Params(idx).locked = true;
                    app.Params(idx).newValue = app.Params(idx).value;
                    app.Params(idx).isChanged = false;
                end
                app.StatusLabel.Text = sprintf( ...
                    '已锁定 %d 个参数（新值保持原值）。', numel(indices));
            end
            app.refreshTable();
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
            dlg = mps.SweepDialog(app.Params, app.LastWorkspace);
            uiwait(dlg.UIFigure);
            result = dlg.Result;
            delete(dlg);
            if ~isstruct(result) || ~isfield(result, 'activeIdx') || ...
                    isempty(result.activeIdx)
                return;   % cancelled
            end
            app.runSweep(result.activeIdx, result.values, ...
                result.overlay, result.xName, result.yNames);
        end

        function summary = runSweep(app, activeIdx, values, overlay, xName, yNames)
            %RUNSWEEP Execute the cartesian product and build reports.
            summary = struct('ok', false, 'sweepRoot', '', 'count', 0, ...
                'report', '', 'overlayPath', '', 'metricsPath', '');
            if isempty(app.SourceFile) || isempty(activeIdx)
                return;
            end

            app.setBusy(true);
            [sweepRoot, d, oldHV, oldVis, cleanupObj] = app.prepareSweep();

            try
                names = {app.Params(activeIdx).name};
                scenarios = mps.sweepScenarios(names, values, 24);
                results = struct('label', {}, 'runDir', {}, 'ok', {}, ...
                    'error', {}, 'figures', {}, 'elapsed', {}, ...
                    'workspaceData', {});

                for k = 1:numel(scenarios)
                    if ~isempty(d) && isvalid(d)
                        d.Value = (k - 1) / numel(scenarios);
                        d.Message = sprintf('运行 %d/%d：%s', ...
                            k, numel(scenarios), scenarios(k).label);
                        drawnow;
                    end
                    runDir = fullfile(sweepRoot, sprintf('run_%02d', k));
                    if ~isfolder(runDir)
                        mkdir(runDir);
                    end

                    params = app.Params;
                    for j = 1:numel(activeIdx)
                        params(activeIdx(j)).newValue = ...
                            num2str(scenarios(k).values{j}, '%.10g');
                        params(activeIdx(j)).use = true;
                    end

                    [tempScript, keepScript] = app.makeTempScript(runDir);
                    mps.applyEdits(app.SourceFile, params, tempScript, ...
                        'NeutralizeCloseAll', true);
                    r = mps.runScript(app.SourceFile, tempScript, runDir);
                    try
                        if ~isfile(keepScript) && ...
                                ~strcmpi(tempScript, keepScript)
                            copyfile(tempScript, keepScript);
                        end
                        if isfile(keepScript)
                            r.scriptPath = keepScript;
                        end
                    catch
                    end
                    app.removeTempScript(tempScript, keepScript);
                    app.handleRunFigures(r);

                    results(end+1) = struct( ...
                        'label', scenarios(k).label, ...
                        'runDir', runDir, 'ok', r.ok, ...
                        'error', r.error, 'figures', {r.figures}, ...
                        'elapsed', r.elapsedSeconds, ...
                        'workspaceData', {r.workspaceData}); %#ok<AGROW>
                end

                if ~isempty(d) && isvalid(d)
                    d.Value = 0.97;
                    d.Message = '生成叠加曲线和报告...';
                    drawnow;
                end

                overlayPath = '';
                if overlay
                    overlayPath = app.makeSweepOverlay(sweepRoot, ...
                        results, xName, yNames);
                end
                metrics = mps.sweepMetrics(results, xName, yNames);

                agg = app.aggregateSweepRun(sweepRoot, results, overlayPath);
                agg.metrics = metrics;
                app.LastRun = agg;
                app.LastWorkspace = agg.workspaceData;
                app.OutputDir = sweepRoot;
                [app.LastReport, metricsPath] = mps.writeSweepReport( ...
                    sweepRoot, app.SourceFile, names, values, scenarios, ...
                    results, overlayPath, metrics);

                app.refreshResults();
                app.refreshWorkspace();
                app.refreshPlotVariables();
                if isempty(agg.log)
                    app.LogArea.Value = {''};
                else
                    app.LogArea.Value = splitlines(agg.log);
                end
                app.ReportButton.Enable = 'on';
                app.FolderButton.Enable = 'on';
                app.CloseFiguresButton.Enable = 'on';
                app.CompareButton.Enable = 'on';

                summary.ok = true;
                summary.sweepRoot = sweepRoot;
                summary.count = numel(results);
                summary.report = app.LastReport;
                summary.overlayPath = overlayPath;
                summary.metricsPath = metricsPath;
                if isempty(metricsPath)
                    app.StatusLabel.Text = sprintf( ...
                        '批量扫描完成：%d 组，%d 张图。报告：%s', ...
                        numel(results), numel(agg.figures), app.LastReport);
                else
                    app.StatusLabel.Text = sprintf( ...
                        '批量扫描完成：%d 组，%d 张图。指标 CSV：%s', ...
                        numel(results), numel(agg.figures), metricsPath);
                end
            catch err
                app.StatusLabel.Text = ['批量扫描失败：' err.message];
                uialert(app.UIFigure, err.message, '批量扫描失败', ...
                    'Icon', 'error');
            end
            clear cleanupObj;
        end

        function [sweepRoot, d, oldHV, oldVis, cleanupObj] = prepareSweep(app)
            base = fileparts(app.SourceFile);
            root = fullfile(base, 'parameter_studio_runs');
            if ~isfolder(root)
                mkdir(root);
            end
            stamp = datestr(now, 'yyyymmdd_HHMMSS');
            sweepRoot = fullfile(root, [stamp '_sweep']);
            n = 2;
            while isfolder(sweepRoot)
                sweepRoot = fullfile(root, sprintf('%s_sweep_%d', stamp, n));
                n = n + 1;
            end
            mkdir(sweepRoot);

            if strcmp(app.UIFigure.Visible, 'on')
                d = uiprogressdlg(app.UIFigure, 'Title', '批量扫描', ...
                    'Message', '准备...', 'Indeterminate', 'off', ...
                    'Value', 0);
            else
                d = [];
            end
            oldHV = app.UIFigure.HandleVisibility;
            app.UIFigure.HandleVisibility = 'off';
            oldVis = get(groot, 'defaultFigureVisible');
            set(groot, 'defaultFigureVisible', 'off');
            cleanupObj = onCleanup(@() app.finishSweep(d, oldHV, oldVis)); %#ok<NASGU>
        end

        function finishSweep(app, d, oldHV, oldVis)
            if ~isempty(d) && isvalid(d)
                delete(d);
            end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                app.UIFigure.HandleVisibility = oldHV;
            end
            set(groot, 'defaultFigureVisible', oldVis);
            app.setBusy(false);
        end

        function [tempScript, keepScript] = makeTempScript(app, runDir)
            keepScript = fullfile(runDir, 'run_script.m');
            runDirSrc = fileparts(app.SourceFile);
            tempScript = fullfile(runDirSrc, ...
                sprintf('mps_sweep_%s.m', datestr(now, 'HHMMSSFFF')));
            if isfile(tempScript)
                tempScript = fullfile(runDirSrc, ...
                    sprintf('mps_sweep_%s_%d.m', datestr(now, 'HHMMSSFFF'), ...
                    randi(9999)));
            end
            % If the source folder is read-only, fall back to the run folder
            % (relative paths may then fail, but the script still runs).
            try
                fid = fopen(tempScript, 'w');
                if fid >= 0
                    fclose(fid);
                    delete(tempScript);
                else
                    tempScript = keepScript;
                end
            catch
                tempScript = keepScript;
            end
        end

        function removeTempScript(app, tempScript, keepScript)
            if ~strcmpi(tempScript, keepScript) && isfile(tempScript)
                try
                    delete(tempScript);
                catch
                end
            end
        end

        function handleRunFigures(app, r)
            if app.KeepFiguresCheck.Value
                for fk = 1:numel(r.figureHandles)
                    if isvalid(r.figureHandles(fk))
                        set(r.figureHandles(fk), 'Visible', 'on');
                    end
                end
            else
                for fk = 1:numel(r.figureHandles)
                    if isvalid(r.figureHandles(fk))
                        delete(r.figureHandles(fk));
                    end
                end
                r.figureHandles = gobjects(0);
            end
        end

        function agg = aggregateSweepRun(app, sweepRoot, results, overlayPath)
            agg = struct();
            agg.ok = true;
            agg.error = '';
            agg.figures = struct('path', {}, 'title', {}, 'figFile', {});
            agg.workspace = struct('name', {}, 'class', {}, 'size', {}, ...
                'min', {}, 'max', {}, 'preview', {});
            agg.workspaceData = struct();
            agg.log = '';
            agg.outDir = sweepRoot;
            agg.scriptPath = '';
            agg.sourceFile = app.SourceFile;
            agg.matFile = '';
            agg.figureHandles = gobjects(0);
            agg.elapsedSeconds = 0;

            if ~isempty(overlayPath)
                agg.figures(end+1) = struct('path', overlayPath, ...
                    'title', '叠加曲线', 'figFile', '');
            end
            for k = 1:numel(results)
                agg.elapsedSeconds = agg.elapsedSeconds + results(k).elapsed;
                for j = 1:numel(results(k).figures)
                    f = results(k).figures(j);
                    agg.figures(end+1) = struct('path', f.path, ...
                        'title', sprintf('%02d · %s · %s', k, ...
                        results(k).label, f.title), 'figFile', f.figFile); %#ok<AGROW>
                end
                if ~isempty(results(k).error)
                    agg.log = [agg.log, sprintf('--- run %02d (%s) ---\n%s\n', ...
                        k, results(k).label, results(k).error)];
                end
            end
            if ~isempty(results)
                agg.workspaceData = results(end).workspaceData;
                agg.workspace = mps.summarizeWorkspace(agg.workspaceData);
            end
        end

        function overlayPath = makeSweepOverlay(app, sweepRoot, results, xName, yNames)
            overlayPath = '';
            if isempty(xName) || strcmp(xName, '(无)') || isempty(yNames)
                return;
            end
            if ischar(yNames)
                yNames = {yNames};
            end
            fig = figure('Visible', 'off', 'Color', 'w');
            half = onCleanup(@() delete(fig)); %#ok<NASGU>
            hold on;
            grid on;
            plotted = 0;
            cmap = lines(max(7, numel(results)));
            styles = {'-', '--', ':', '-.'};
            for k = 1:numel(results)
                ws = results(k).workspaceData;
                if ~isstruct(ws) || ~isfield(ws, xName)
                    continue;
                end
                x = ws.(xName);
                if ~(isnumeric(x) || islogical(x)) || ~isvector(x)
                    continue;
                end
                for j = 1:numel(yNames)
                    if ~isfield(ws, yNames{j})
                        continue;
                    end
                    y = ws.(yNames{j});
                    if ~(isnumeric(y) || islogical(y)) || ~isvector(y) || ...
                            numel(x) ~= numel(y)
                        continue;
                    end
                    if numel(yNames) == 1
                        label = results(k).label;
                    else
                        label = sprintf('%s | %s', ...
                            results(k).label, yNames{j});
                    end
                    style = styles{mod(j - 1, numel(styles)) + 1};
                    plot(x, y, style, 'LineWidth', 1.2, ...
                        'Color', cmap(k, :), 'DisplayName', label);
                    plotted = plotted + 1;
                end
            end
            if plotted == 0
                return;
            end
            xlabel(xName, 'Interpreter', 'none');
            ylabel('值');
            title('批量扫描叠加曲线');
            legend('Location', 'eastoutside', 'Interpreter', 'none', ...
                'FontSize', 9);
            overlayPath = fullfile(sweepRoot, 'overlay.png');
            try
                exportgraphics(fig, overlayPath, 'Resolution', 150, ...
                    'BackgroundColor', 'white');
            catch
                overlayPath = '';
            end
            clear half;
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
                'CurrentOutDir', app.OutputDir);
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
        function refreshResults(app)
            r = app.LastRun;
            if ~isfield(r, 'figures') || isempty(r.figures)
                app.FigureDrop.Items = {'(无图)'};
                app.FigureDrop.Value = '(无图)';
                app.FigurePaths = {};
                app.FigureImage.ImageSource = '';
                app.FigureImage.Visible = 'off';
                return;
            end
            items = cell(1, numel(r.figures));
            app.FigurePaths = cell(1, numel(r.figures));
            for k = 1:numel(r.figures)
                title = r.figures(k).title;
                if isempty(title)
                    title = sprintf('图 %d', k);
                end
                items{k} = sprintf('%d. %s', k, title);
                app.FigurePaths{k} = r.figures(k).path;
            end
            app.FigureDrop.Items = items;
            app.FigureDrop.Value = items{1};
            app.showFigure();
        end

        function showFigure(app)
            if isempty(app.FigurePaths)
                app.FigureImage.ImageSource = '';
                app.FigureImage.Visible = 'off';
                return;
            end
            idx = find(strcmp(app.FigureDrop.Items, app.FigureDrop.Value), 1);
            if isempty(idx) || idx > numel(app.FigurePaths)
                return;
            end
            path = app.FigurePaths{idx};
            if isfile(path)
                app.FigureImage.ImageSource = path;
                app.FigureImage.Visible = 'on';
            else
                app.FigureImage.ImageSource = '';
                app.FigureImage.Visible = 'off';
            end
        end

        function refreshWorkspace(app)
            ws = struct([]);
            if isfield(app.LastRun, 'workspace')
                ws = app.LastRun.workspace;
            end
            data = cell(numel(ws), 6);
            for k = 1:numel(ws)
                data{k,1} = ws(k).name;
                data{k,2} = ws(k).class;
                data{k,3} = ws(k).size;
                data{k,4} = fmtValue(ws(k).min);
                data{k,5} = fmtValue(ws(k).max);
                data{k,6} = ws(k).preview;
            end
            app.WorkspaceTable.Data = data;
        end

        function refreshPlotVariables(app)
            names = {};
            if isstruct(app.LastWorkspace)
                fields = fieldnames(app.LastWorkspace);
                for k = 1:numel(fields)
                    v = app.LastWorkspace.(fields{k});
                    if (isnumeric(v) || islogical(v)) && isvector(v) && ...
                            numel(v) >= 2 && numel(v) <= 1e6 && isreal(v)
                        names{end+1} = fields{k}; %#ok<AGROW>
                    end
                end
            end
            names = sort(names);
            if isempty(names)
                app.XDrop.Items = {'(无)'};
                app.XDrop.Value = '(无)';
                app.YList.Items = {'(无)'};
                app.YList.Value = {'(无)'};
                app.PlotButton.Enable = 'off';
                app.SavePlotButton.Enable = 'off';
                app.ExportCsvButton.Enable = 'off';
                app.PlotStatus.Text = '没有可绘制的数值向量。';
                return;
            end
            app.XDrop.Items = names;
            if any(strcmp(names, 't'))
                app.XDrop.Value = 't';
            else
                app.XDrop.Value = names{1};
            end
            ys = names(~strcmp(names, app.XDrop.Value));
            if isempty(ys)
                ys = names;
            end
            app.YList.Items = ys;
            app.YList.Value = ys(1:min(2, numel(ys)));
            app.PlotButton.Enable = 'on';
            app.SavePlotButton.Enable = 'on';
            app.ExportCsvButton.Enable = 'on';
            txt = strjoin(names, ', ');
            if numel(txt) > 100
                txt = [txt(1:97), '...'];
            end
            app.PlotStatus.Text = ['可绘制变量：', txt];
        end

        function onPlot(app)
            if ~isstruct(app.LastWorkspace) || isempty(fieldnames(app.LastWorkspace))
                return;
            end
            xName = app.XDrop.Value;
            if isempty(xName) || strcmp(xName, '(无)')
                return;
            end
            yNames = app.YList.Value;
            if ischar(yNames)
                yNames = {yNames};
            end
            if isempty(yNames) || (numel(yNames) == 1 && strcmp(yNames{1}, '(无)'))
                return;
            end
            x = app.LastWorkspace.(xName);
            cla(app.UIAxes);
            hold(app.UIAxes, 'on');
            leg = {};
            for k = 1:numel(yNames)
                if ~isfield(app.LastWorkspace, yNames{k})
                    continue;
                end
                y = app.LastWorkspace.(yNames{k});
                if numel(y) ~= numel(x)
                    continue;
                end
                plot(app.UIAxes, x, y, 'LineWidth', 1.2);
                leg{end+1} = yNames{k}; %#ok<AGROW>
            end
            hold(app.UIAxes, 'off');
            grid(app.UIAxes, 'on');
            xlabel(app.UIAxes, xName, 'Interpreter', 'none');
            ylabel(app.UIAxes, '值');
            if ~isempty(leg)
                legend(app.UIAxes, leg, 'Interpreter', 'none', 'Location', 'best');
            end
            title(app.UIAxes, '工作区变量');
            app.PlotStatus.Text = sprintf('已绘制 %d 条曲线。', numel(leg));
            drawnow;
        end

        function onSavePlot(app)
            if isempty(app.OutputDir) || ~isfolder(app.OutputDir)
                uialert(app.UIFigure, '请先运行一次脚本。', '没有输出目录', ...
                    'Icon', 'warning');
                return;
            end
            path = fullfile(app.OutputDir, 'figures', 'custom_plot.png');
            try
                exportgraphics(app.UIAxes, path, 'Resolution', 150, ...
                    'BackgroundColor', 'white');
            catch err
                uialert(app.UIFigure, err.message, '保存失败', 'Icon', 'error');
                return;
            end
            if isstruct(app.LastRun) && isfield(app.LastRun, 'figures')
                keep = true(1, numel(app.LastRun.figures));
                for k = 1:numel(app.LastRun.figures)
                    if strcmp(app.LastRun.figures(k).path, path)
                        keep(k) = false;
                    end
                end
                app.LastRun.figures = app.LastRun.figures(keep);
            else
                app.LastRun.figures = struct('path', {}, 'title', {}, 'figFile', {});
            end
            app.LastRun.figures(end+1) = struct('path', path, ...
                'title', '自定义工作区图', 'figFile', '');
            app.CustomPlotPath = path;
            app.refreshResults();
            % Select the custom figure in the dropdown.
            for k = 1:numel(app.FigureDrop.Items)
                if contains(app.FigureDrop.Items{k}, '自定义工作区图')
                    app.FigureDrop.Value = app.FigureDrop.Items{k};
                    app.showFigure();
                    break;
                end
            end
            app.LastReport = mps.writeReport(app.OutputDir, app.SourceFile, ...
                app.Params, app.LastRun);
            app.ReportButton.Enable = 'on';
            app.StatusLabel.Text = '自定义图已保存，HTML 报告已更新。';
        end

        function onExportCurve(app)
            %ONEXPORTCURVE Write X/Y curve data to curve_data.csv.
            if isempty(app.OutputDir) || ~isfolder(app.OutputDir)
                uialert(app.UIFigure, '请先运行一次脚本。', '没有输出目录', ...
                    'Icon', 'warning');
                return;
            end
            if ~isstruct(app.LastWorkspace) || isempty(fieldnames(app.LastWorkspace))
                uialert(app.UIFigure, '工作区里没有可导出的变量。', ...
                    '没有数据', 'Icon', 'warning');
                return;
            end
            xName = app.XDrop.Value;
            if isempty(xName) || strcmp(xName, '(无)')
                return;
            end
            yNames = app.YList.Value;
            if ischar(yNames)
                yNames = {yNames};
            end
            if isempty(yNames) || (numel(yNames) == 1 && strcmp(yNames{1}, '(无)'))
                return;
            end
            x = app.LastWorkspace.(xName);
            cols = {x(:)};
            names = {matlab.lang.makeValidName(xName)};
            for k = 1:numel(yNames)
                if ~isfield(app.LastWorkspace, yNames{k})
                    continue;
                end
                y = app.LastWorkspace.(yNames{k});
                if numel(y) ~= numel(x)
                    continue;
                end
                cols{end+1} = y(:); %#ok<AGROW>
                names{end+1} = matlab.lang.makeValidName(yNames{k}); %#ok<AGROW>
            end
            if numel(cols) < 2
                uialert(app.UIFigure, 'X/Y 变量长度不一致，无法导出。', ...
                    '导出失败', 'Icon', 'warning');
                return;
            end
            names = matlab.lang.makeUniqueStrings(names);
            data = [cols{:}];
            csvPath = fullfile(app.OutputDir, 'curve_data.csv');
            try
                T = array2table(data, 'VariableNames', names);
                writetable(T, csvPath, 'Encoding', 'UTF-8');
            catch err
                uialert(app.UIFigure, err.message, '导出失败', 'Icon', 'error');
                return;
            end
            app.StatusLabel.Text = sprintf('曲线数据已导出：%s', csvPath);
            uialert(app.UIFigure, sprintf('已导出 %d 行 × %d 列：\n%s', ...
                size(data, 1), size(data, 2), csvPath), ...
                '导出成功', 'Icon', 'info');
        end

        % -----------------------------------------------------------------
        function onSaveTuned(app)
            if isempty(app.SourceFile)
                return;
            end
            if ~app.ensureSourceCurrent('保存')
                return;
            end
            [~, base] = fileparts(app.SourceFile);
            defaultName = fullfile(fileparts(app.SourceFile), [base '_tuned.m']);
            [file, path] = uiputfile({'*.m', 'MATLAB 脚本 (*.m)'}, ...
                '保存调参后的脚本', defaultName);
            if isequal(file, 0)
                return;
            end
            target = fullfile(path, file);
            if strcmpi(target, app.SourceFile)
                uialert(app.UIFigure, ...
                    '不能覆盖原文件。请使用 _tuned 后缀或其他文件名。', ...
                    '保存失败', 'Icon', 'warning');
                return;
            end

            stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
            footer = sprintf('%% ---- MATLAB Parameter Studio overrides (%s) ----\n', stamp);
            footer = [footer, sprintf('%% 源文件: %s\n', app.SourceFile)];
            anyChange = false;
            for k = 1:numel(app.Params)
                p = app.Params(k);
                if p.use && ~strcmp(strtrim(p.value), strtrim(p.newValue))
                    ann = annotationText(p);
                    if isempty(ann)
                        annSuffix = '';
                    else
                        annSuffix = ['  % ' ann];
                    end
                    footer = [footer, sprintf('%%   %s = %s  (原值 %s, 第 %d 行)%s\n', ...
                        p.name, p.newValue, p.value, p.line, annSuffix)]; %#ok<AGROW>
                    anyChange = true;
                end
            end
            if ~anyChange
                footer = [footer, sprintf('%%   本次没有修改参数。\n')];
            end

            try
                original = fileread(app.SourceFile);
                [outText, applied] = mps.applyEdits(app.SourceFile, ...
                    app.Params, '', 'Footer', footer);
            catch err
                uialert(app.UIFigure, err.message, '保存失败', 'Icon', 'error');
                return;
            end

            diffLines = mps.textDiff(original, outText);
            dlg = mps.DiffDialog(sprintf('保存到：%s', target), diffLines);
            uiwait(dlg.UIFigure);
            confirmed = dlg.Result;
            delete(dlg);
            if ~confirmed
                app.StatusLabel.Text = '已取消保存。';
                return;
            end

            fid = fopen(target, 'w', 'n', 'UTF-8');
            if fid < 0
                uialert(app.UIFigure, '无法写入目标文件。', ...
                    '保存失败', 'Icon', 'error');
                return;
            end
            fprintf(fid, '%s', outText);
            fclose(fid);

            [folder, outBase] = fileparts(target);
            jsonPath = fullfile(folder, [outBase '_params.json']);
            fid = fopen(jsonPath, 'w', 'n', 'UTF-8');
            if fid >= 0
                fprintf(fid, '%s', jsonencode(applied));
                fclose(fid);
            end

            app.StatusLabel.Text = sprintf('已保存调参脚本：%s', target);
            uialert(app.UIFigure, sprintf( ...
                '已保存脚本：\n%s\n\n参数记录：\n%s\n\n脚本可以直接在 MATLAB 中运行。', ...
                target, jsonPath), '保存成功', 'Icon', 'info');
        end

        function onExportParams(app)
            if isempty(app.SourceFile)
                return;
            end
            [~, base] = fileparts(app.SourceFile);
            defaultName = fullfile(fileparts(app.SourceFile), [base '_params.json']);
            [file, path] = uiputfile({'*.json', 'JSON 文件 (*.json)'}, ...
                '导出参数集', defaultName);
            if isequal(file, 0)
                return;
            end
            target = fullfile(path, file);
            fid = fopen(target, 'w', 'n', 'UTF-8');
            if fid < 0
                uialert(app.UIFigure, '无法写入文件。', '导出失败', 'Icon', 'error');
                return;
            end
            fprintf(fid, '%s', jsonencode(app.Params));
            fclose(fid);
            app.StatusLabel.Text = sprintf('已导出参数集：%s', target);
        end

        function onOpenReport(app)
            if isempty(app.LastReport) || ~isfile(app.LastReport)
                uialert(app.UIFigure, '还没有生成报告，请先运行。', ...
                    '没有报告', 'Icon', 'warning');
                return;
            end
            try
                web(app.LastReport, '-browser');
            catch
                try
                    winopen(app.LastReport);
                catch err
                    uialert(app.UIFigure, err.message, '打开失败', 'Icon', 'error');
                end
            end
        end

        function onOpenFolder(app)
            if isempty(app.OutputDir) || ~isfolder(app.OutputDir)
                uialert(app.UIFigure, '还没有输出目录，请先运行。', ...
                    '没有输出', 'Icon', 'warning');
                return;
            end
            try
                mps.openPath(app.OutputDir);
            catch err
                uialert(app.UIFigure, err.message, '打开失败', 'Icon', 'error');
            end
        end

        function onCloseFigures(app)
            if isfield(app.LastRun, 'figureHandles')
                hs = app.LastRun.figureHandles;
                for k = 1:numel(hs)
                    if isvalid(hs(k))
                        close(hs(k));
                    end
                end
                app.LastRun.figureHandles = gobjects(0);
            end
            app.StatusLabel.Text = '已关闭本次运行产生的图窗。';
        end

        function onClose(app)
            try
                if app.SessionDirty
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
                app.SweepButton, app.BulkButton, ...
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
                elseif app.IsFunctionFile
                    app.RunButton.Enable = 'off';
                    app.SweepButton.Enable = 'off';
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
                    end
                end
                if isempty(app.SourceFile)
                    app.CompareButton.Enable = 'off';
                else
                    app.CompareButton.Enable = 'on';
                end
                if isempty(app.LastReport)
                    app.ReportButton.Enable = 'off';
                end
                if isempty(app.OutputDir)
                    app.FolderButton.Enable = 'off';
                end
                if ~isfield(app.LastRun, 'figures') || isempty(app.LastRun.figures)
                    app.CloseFiguresButton.Enable = 'off';
                end
                if ~isstruct(app.LastWorkspace) || isempty(fieldnames(app.LastWorkspace))
                    app.PlotButton.Enable = 'off';
                    app.SavePlotButton.Enable = 'off';
                    app.ExportCsvButton.Enable = 'off';
                end
            end
            app.updateUndoButtons();
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
function s = annotationText(p)
%ANNOTATIONTEXT Format a parameter's AI annotation for the table/report.
    s = '';
    if isfield(p, 'description')
        s = p.description;
    end
    if isfield(p, 'unit') && ~isempty(p.unit)
        if isempty(s)
            s = ['[' p.unit ']'];
        else
            s = sprintf('%s (%s)', s, p.unit);
        end
    end
    if numel(s) > 200
        s = [s(1:197), '...'];
    end
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

% -------------------------------------------------------------------------
function s = categoryLabel(c)
    switch c
        case 'assignment', s = '赋值';
        case 'struct', s = '结构体字段';
        case 'array', s = '数组元素';
        case 'range', s = '范围';
        case 'expression', s = '表达式';
        case 'argument', s = '函数参数';
        case 'index', s = '索引';
        case 'style', s = '绘图样式';
        case 'layout', s = '界面布局';
        case 'size', s = '数组尺寸';
        case 'control', s = '控制流';
        case 'function', s = '函数体';
        case 'annotated', s = '注释标记';
        otherwise, s = c;
    end
end

% -------------------------------------------------------------------------
function s = fmtValue(v)
    if isempty(v)
        s = '';
    elseif isnumeric(v) || islogical(v)
        try
            s = num2str(v, '%.6g');
        catch
            s = num2str(v);
        end
    else
        s = char(v);
    end
end
