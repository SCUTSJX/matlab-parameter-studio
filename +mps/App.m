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
        FolderButton, ExportButton, CloseFiguresButton
        SelectAllButton, ResetButton, PlotButton, SavePlotButton, ExportCsvButton
        OpenReportInline
        SourceLines = {}
        VisibleIdx = []
        IsFunctionFile = false
        CustomPlotPath = ''
        Busy = false
    end

    methods
        function app = App()
            app.createUI();
            app.UIFigure.UserData = app;
        end

        function delete(app)
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end

        function loadFile(app, filePath)
            %LOADFILE Scan a .m file and populate the parameter table.
            filePath = char(filePath);
            if ~isfile(filePath)
                uialert(app.UIFigure, sprintf('文件不存在：\n%s', filePath), ...
                    '打开失败', 'Icon', 'error');
                return;
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

            app.SourceFile = filePath;
            app.Params = p;
            app.LastRun = struct();
            app.LastWorkspace = struct();
            app.LastReport = '';
            app.OutputDir = '';
            app.CustomPlotPath = '';
            app.FigurePaths = {};

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
            app.ReportButton.Enable = 'off';
            app.FolderButton.Enable = 'off';
            app.CloseFiguresButton.Enable = 'off';
            app.PlotButton.Enable = 'off';
            app.SavePlotButton.Enable = 'off';
            app.ExportCsvButton.Enable = 'off';

            app.refreshTable();
            nUse = sum([p.use]);
            if app.IsFunctionFile
                app.StatusLabel.Text = sprintf( ...
                    '已载入函数文件：识别 %d 个数字（%d 个推荐）。可保存调参后的函数，但不能直接运行。', ...
                    numel(p), nUse);
            else
                app.StatusLabel.Text = sprintf('已载入：识别 %d 个数字，其中 %d 个推荐参数。', ...
                    numel(p), nUse);
            end
            drawnow;
        end

        function setParam(app, name, value)
            %SETPARAM Set a parameter by name (used by tests and automation).
            if isnumeric(value) || islogical(value)
                value = num2str(value);
            end
            value = char(value);
            for k = 1:numel(app.Params)
                if strcmp(app.Params(k).name, name)
                    app.Params(k).newValue = value;
                    app.Params(k).isChanged = ~strcmp(strtrim(app.Params(k).value), ...
                        strtrim(value));
                    app.Params(k).use = true;
                end
            end
            app.refreshTable();
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

            root = uigridlayout(app.UIFigure, [3 1]);
            root.RowHeight = {48, '1x', 26};
            root.Padding = [10 10 10 8];
            root.RowSpacing = 8;

            tb = uigridlayout(root, [1 9]);
            tb.Layout.Row = 1;
            tb.ColumnWidth = {108, '1x', 88, 78, 132, 100, 100, 100, 100};
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

            app.FolderButton = uibutton(tb, 'Text', '打开输出', ...
                'Enable', 'off', 'ButtonPushedFcn', @(s, e) app.onOpenFolder());
            app.FolderButton.Layout.Column = 7;

            app.ExportButton = uibutton(tb, 'Text', '导出参数', ...
                'Enable', 'off', 'ButtonPushedFcn', @(s, e) app.onExportParams());
            app.ExportButton.Layout.Column = 8;

            app.CloseFiguresButton = uibutton(tb, 'Text', '关闭结果图', ...
                'Enable', 'off', 'ButtonPushedFcn', @(s, e) app.onCloseFigures());
            app.CloseFiguresButton.Layout.Column = 9;

            main = uigridlayout(root, [1 2]);
            main.Layout.Row = 2;
            main.ColumnWidth = {'1x', '0.72x'};
            main.Padding = [0 0 0 0];
            main.ColumnSpacing = 8;

            lp = uipanel(main, 'Title', '参数', 'FontWeight', 'bold');
            lp.Layout.Column = 1;
            lg = uigridlayout(lp, [3 1]);
            lg.RowHeight = {34, '1x', 96};
            lg.Padding = [8 8 8 8];
            lg.RowSpacing = 6;

            fg = uigridlayout(lg, [1 5]);
            fg.Layout.Row = 1;
            fg.ColumnWidth = {120, '1x', 150, 92, 92};
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

            app.Table = uitable(lg, ...
                'ColumnName', {'使用', '参数', '当前值', '新值', '行', '类型', '说明'}, ...
                'ColumnEditable', [true false false true false false false], ...
                'ColumnFormat', {'logical', 'char', 'char', 'char', 'numeric', 'char', 'char'}, ...
                'ColumnWidth', {48, 205, 85, 85, 42, 85, '1x'}, ...
                'RowName', [], ...
                'CellEditCallback', @(s, e) app.onCellEdit(s, e), ...
                'CellSelectionCallback', @(s, e) app.onCellSelect(s, e));
            app.Table.Layout.Row = 2;

            app.SourcePreview = uitextarea(lg, 'Editable', 'off', ...
                'FontName', 'Consolas', 'FontSize', 11, 'Value', {''});
            app.SourcePreview.Layout.Row = 3;

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
                'Text', '就绪。打开一个 .m 文件开始。', ...
                'FontColor', [0.35 0.35 0.35]);
            app.StatusLabel.Layout.Row = 3;
        end

        % -----------------------------------------------------------------
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
            app.loadFile(app.SourceFile);
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

            app.setBusy(true);
            d = uiprogressdlg(app.UIFigure, 'Title', 'MATLAB Parameter Studio', ...
                'Message', '准备参数...', 'Indeterminate', 'on');
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

                d.Message = '运行 MATLAB 脚本...';
                drawnow;
                r = mps.runScript(app.SourceFile, tempScript, outDir);
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

                d.Message = '生成 HTML 报告...';
                drawnow;
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

                if r.ok
                    app.StatusLabel.Text = sprintf( ...
                        '完成：%d 个参数参与，%d 张图，%d 个变量，耗时 %.2f s。', ...
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
        function refreshTable(app)
            if isempty(app.Params)
                app.Table.Data = cell(0, 7);
                app.VisibleIdx = [];
                app.CountLabel.Text = '0 / 0';
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
                    hay = lower(sprintf('%s %s %s %d', ...
                        p.name, p.note, p.context, p.line));
                    keep = contains(hay, q);
                end
                if keep
                    idx(end+1) = k; %#ok<AGROW>
                end
            end
            app.VisibleIdx = idx;

            data = cell(numel(idx), 7);
            for j = 1:numel(idx)
                p = app.Params(idx(j));
                note = p.note;
                if isempty(note)
                    note = p.context;
                end
                if numel(note) > 120
                    note = [note(1:117), '...'];
                end
                data{j,1} = p.use;
                data{j,2} = p.name;
                data{j,3} = p.value;
                data{j,4} = p.newValue;
                data{j,5} = p.line;
                data{j,6} = categoryLabel(p.category);
                data{j,7} = note;
            end
            app.Table.Data = data;
            app.CountLabel.Text = sprintf('%d / %d · 已修改 %d', ...
                numel(idx), numel(app.Params), sum([app.Params.isChanged]));

            rec = [app.Params.score] >= 3;
            if any(rec)
                if all([app.Params(rec).use])
                    app.SelectAllButton.Text = '取消全选';
                else
                    app.SelectAllButton.Text = '全选推荐';
                end
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
                app.Params(idx).use = logical(event.NewData);
            elseif col == 4
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
                app.Params(idx).newValue = newVal;
                app.Params(idx).isChanged = ~strcmp( ...
                    strtrim(app.Params(idx).value), newVal);
            end
            app.refreshTable();
        end

        function onCellSelect(app, ~, event)
            if isempty(event.Indices) || isempty(app.VisibleIdx)
                app.SourcePreview.Value = {''};
                return;
            end
            row = event.Indices(1);
            if row < 1 || row > numel(app.VisibleIdx)
                app.SourcePreview.Value = {''};
                return;
            end
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
            for k = 1:numel(app.Params)
                app.Params(k).newValue = app.Params(k).value;
                app.Params(k).isChanged = false;
            end
            app.refreshTable();
            app.StatusLabel.Text = '已把所有新值重置为当前值。';
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
                    footer = [footer, sprintf('%%   %s = %s  (原值 %s, 第 %d 行)\n', ...
                        p.name, p.newValue, p.value, p.line)]; %#ok<AGROW>
                    anyChange = true;
                end
            end
            if ~anyChange
                footer = [footer, sprintf('%%   本次没有修改参数。\n')];
            end

            try
                [~, applied] = mps.applyEdits(app.SourceFile, app.Params, ...
                    target, 'Footer', footer);
            catch err
                uialert(app.UIFigure, err.message, '保存失败', 'Icon', 'error');
                return;
            end

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
                if ispc
                    winopen(app.OutputDir);
                else
                    system(['xdg-open "' app.OutputDir '" &']);
                end
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
                elseif app.IsFunctionFile
                    app.RunButton.Enable = 'off';
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
            drawnow;
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
