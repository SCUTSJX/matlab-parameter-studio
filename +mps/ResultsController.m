classdef ResultsController < handle
%RESULTSCONTROLLER Own the result figures, workspace, plotting and exports.
%
%   results = mps.ResultsController(handles...)
%
%   The controller holds LastRun / LastWorkspace / OutputDir / LastReport
%   and drives the 结果图 / 工作区 / 绘图 tabs.  App only forwards button
%   callbacks and passes SourceFile/Params when a report must be rewritten.

    properties
        LastRun = struct()
        LastWorkspace = struct()
        OutputDir = ''
        LastReport = ''
    end

    properties (Access = private)
        UIFigure
        FigureDrop
        FigureImage
        WorkspaceTable
        XDrop
        YList
        UIAxes
        PlotStatus
        PlotButton
        SavePlotButton
        ExportCsvButton
        ReportButton
        StatusLabel
        FigurePaths = {}
        CustomPlotPath = ''
    end

    methods
        function obj = ResultsController(uiFigure, figureDrop, figureImage, ...
                workspaceTable, xDrop, yList, uiAxes, plotStatus, ...
                plotButton, savePlotButton, exportCsvButton, reportButton, ...
                statusLabel)
            obj.UIFigure = uiFigure;
            obj.FigureDrop = figureDrop;
            obj.FigureImage = figureImage;
            obj.WorkspaceTable = workspaceTable;
            obj.XDrop = xDrop;
            obj.YList = yList;
            obj.UIAxes = uiAxes;
            obj.PlotStatus = plotStatus;
            obj.PlotButton = plotButton;
            obj.SavePlotButton = savePlotButton;
            obj.ExportCsvButton = exportCsvButton;
            obj.ReportButton = reportButton;
            obj.StatusLabel = statusLabel;
        end

        function clear(obj)
            obj.LastRun = struct();
            obj.LastWorkspace = struct();
            obj.OutputDir = '';
            obj.LastReport = '';
            obj.FigurePaths = {};
            obj.CustomPlotPath = '';

            noFigure = mps.tr('(无图)', '(No figures)');
            noneLabel = mps.tr('(无)', '(None)');
            obj.FigureDrop.Items = {noFigure};
            obj.FigureDrop.Value = noFigure;
            obj.FigureImage.ImageSource = '';
            obj.FigureImage.Visible = 'off';
            obj.WorkspaceTable.Data = cell(0, 6);
            obj.XDrop.Items = {noneLabel};
            obj.XDrop.Value = noneLabel;
            obj.YList.Items = {noneLabel};
            obj.YList.Value = {noneLabel};
            obj.PlotButton.Enable = 'off';
            obj.SavePlotButton.Enable = 'off';
            obj.ExportCsvButton.Enable = 'off';
            obj.PlotStatus.Text = mps.tr( ...
                '运行脚本后，可选择工作区变量绘图。', ...
                'Run a script to plot workspace variables here.');
            cla(obj.UIAxes);
            title(obj.UIAxes, mps.tr('运行后在这里绘图', ...
                'Plots appear here after a run'));
        end

        function refreshAll(obj)
            obj.refreshResults();
            obj.refreshWorkspace();
            obj.refreshPlotVariables();
        end

        function refreshResults(obj)
            r = obj.LastRun;
            if ~isfield(r, 'figures') || isempty(r.figures)
                noFigure = mps.tr('(无图)', '(No figures)');
                obj.FigureDrop.Items = {noFigure};
                obj.FigureDrop.Value = noFigure;
                obj.FigurePaths = {};
                obj.FigureImage.ImageSource = '';
                obj.FigureImage.Visible = 'off';
                return;
            end
            items = cell(1, numel(r.figures));
            obj.FigurePaths = cell(1, numel(r.figures));
            for k = 1:numel(r.figures)
                title = r.figures(k).title;
                if isempty(title)
                    title = mps.tr('图 %d', 'Figure %d', k);
                end
                items{k} = sprintf('%d. %s', k, title);
                obj.FigurePaths{k} = r.figures(k).path;
            end
            obj.FigureDrop.Items = items;
            obj.FigureDrop.Value = items{1};
            obj.showFigure();
        end

        function showFigure(obj)
            if isempty(obj.FigurePaths)
                obj.FigureImage.ImageSource = '';
                obj.FigureImage.Visible = 'off';
                return;
            end
            idx = find(strcmp(obj.FigureDrop.Items, obj.FigureDrop.Value), 1);
            if isempty(idx) || idx > numel(obj.FigurePaths)
                return;
            end
            path = obj.FigurePaths{idx};
            if isfile(path)
                obj.FigureImage.ImageSource = path;
                obj.FigureImage.Visible = 'on';
            else
                obj.FigureImage.ImageSource = '';
                obj.FigureImage.Visible = 'off';
            end
        end

        function refreshWorkspace(obj)
            ws = struct([]);
            if isfield(obj.LastRun, 'workspace')
                ws = obj.LastRun.workspace;
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
            obj.WorkspaceTable.Data = data;
        end

        function refreshPlotVariables(obj)
            noneLabel = mps.tr('(无)', '(None)');
            names = {};
            matFile = obj.workspaceMatFile();
            if ~isempty(matFile) && isfile(matFile)
                try
                    vars = whos('-file', matFile);
                    for k = 1:numel(vars)
                        cls = vars(k).class;
                        if ~(strcmp(cls, 'double') || strcmp(cls, 'single') || ...
                                strcmp(cls, 'logical') || ...
                                startsWith(cls, 'int') || startsWith(cls, 'uint'))
                            continue;
                        end
                        sz = vars(k).size;
                        if sum(sz > 1) > 1 || prod(sz) < 2 || prod(sz) > 1e6
                            continue;
                        end
                        names{end+1} = vars(k).name; %#ok<AGROW>
                    end
                catch err
                    mps.logWarning('读取工作区变量列表', err);
                end
            elseif isstruct(obj.LastWorkspace)
                fields = fieldnames(obj.LastWorkspace);
                for k = 1:numel(fields)
                    v = obj.LastWorkspace.(fields{k});
                    if (isnumeric(v) || islogical(v)) && isvector(v) && ...
                            numel(v) >= 2 && numel(v) <= 1e6 && isreal(v)
                        names{end+1} = fields{k}; %#ok<AGROW>
                    end
                end
            end
            names = sort(names);
            if isempty(names)
                obj.XDrop.Items = {noneLabel};
                obj.XDrop.Value = noneLabel;
                obj.YList.Items = {noneLabel};
                obj.YList.Value = {noneLabel};
                obj.PlotButton.Enable = 'off';
                obj.SavePlotButton.Enable = 'off';
                obj.ExportCsvButton.Enable = 'off';
                obj.PlotStatus.Text = mps.tr('没有可绘制的数值向量。', ...
                    'No numeric vectors are available to plot.');
                return;
            end
            obj.XDrop.Items = names;
            if any(strcmp(names, 't'))
                obj.XDrop.Value = 't';
            else
                obj.XDrop.Value = names{1};
            end
            ys = names(~strcmp(names, obj.XDrop.Value));
            if isempty(ys)
                ys = names;
            end
            obj.YList.Items = ys;
            obj.YList.Value = ys(1:min(2, numel(ys)));
            obj.PlotButton.Enable = 'on';
            obj.SavePlotButton.Enable = 'on';
            obj.ExportCsvButton.Enable = 'on';
            txt = strjoin(names, ', ');
            if numel(txt) > 100
                txt = [txt(1:97), '...'];
            end
            obj.PlotStatus.Text = [ ...
                mps.tr('可绘制变量：', 'Plottable variables: '), txt];
        end

        function plotWorkspace(obj, xName, yNames)
            if ischar(yNames) || isstring(yNames)
                yNames = cellstr(yNames);
            end
            xName = char(xName);
            if any(strcmp(obj.XDrop.Items, xName))
                obj.XDrop.Value = xName;
            else
                return;
            end
            yNames = yNames(ismember(yNames, obj.YList.Items));
            if isempty(yNames)
                return;
            end
            obj.YList.Value = yNames;
            obj.onPlot();
        end

        function onPlot(obj)
            noneLabel = mps.tr('(无)', '(None)');
            xName = obj.XDrop.Value;
            if isempty(xName) || strcmp(xName, noneLabel)
                return;
            end
            yNames = obj.YList.Value;
            if ischar(yNames)
                yNames = {yNames};
            end
            if isempty(yNames) || (numel(yNames) == 1 && ...
                    strcmp(yNames{1}, noneLabel))
                return;
            end
            S = obj.loadVariables([{xName}, yNames]);
            if ~isfield(S, xName)
                return;
            end
            x = S.(xName);
            cla(obj.UIAxes);
            hold(obj.UIAxes, 'on');
            leg = {};
            for k = 1:numel(yNames)
                if ~isfield(S, yNames{k})
                    continue;
                end
                y = S.(yNames{k});
                if numel(y) ~= numel(x)
                    continue;
                end
                plot(obj.UIAxes, x, y, 'LineWidth', 1.2);
                leg{end+1} = yNames{k}; %#ok<AGROW>
            end
            hold(obj.UIAxes, 'off');
            grid(obj.UIAxes, 'on');
            xlabel(obj.UIAxes, xName, 'Interpreter', 'none');
            ylabel(obj.UIAxes, mps.tr('值', 'Value'));
            if ~isempty(leg)
                legend(obj.UIAxes, leg, 'Interpreter', 'none', ...
                    'Location', 'best');
            end
            title(obj.UIAxes, mps.tr('工作区变量', 'Workspace variables'));
            obj.PlotStatus.Text = mps.tr('已绘制 %d 条曲线。', ...
                'Plotted %d curves.', numel(leg));
            drawnow;
        end

        function savePlot(obj, sourceFile, params)
            if isempty(obj.OutputDir) || ~isfolder(obj.OutputDir)
                obj.alert(mps.tr('请先运行一次脚本。', ...
                    'Run a script first.'), ...
                    mps.tr('没有输出目录', 'No output folder'), ...
                    'Icon', 'warning');
                return;
            end
            path = fullfile(obj.OutputDir, 'figures', 'custom_plot.png');
            try
                exportgraphics(obj.UIAxes, path, 'Resolution', 150, ...
                    'BackgroundColor', 'white');
            catch err
                obj.alert(err.message, mps.tr('保存失败', 'Save failed'), ...
                    'Icon', 'error');
                return;
            end
            if isstruct(obj.LastRun) && isfield(obj.LastRun, 'figures')
                keep = true(1, numel(obj.LastRun.figures));
                for k = 1:numel(obj.LastRun.figures)
                    if strcmp(obj.LastRun.figures(k).path, path)
                        keep(k) = false;
                    end
                end
                obj.LastRun.figures = obj.LastRun.figures(keep);
            else
                obj.LastRun.figures = struct('path', {}, ...
                    'title', {}, 'figFile', {});
            end
            customTitle = mps.tr('自定义工作区图', ...
                'Custom workspace plot');
            obj.LastRun.figures(end+1) = struct('path', path, ...
                'title', customTitle, 'figFile', '');
            obj.CustomPlotPath = path;
            obj.refreshResults();
            for k = 1:numel(obj.FigureDrop.Items)
                if contains(obj.FigureDrop.Items{k}, customTitle)
                    obj.FigureDrop.Value = obj.FigureDrop.Items{k};
                    obj.showFigure();
                    break;
                end
            end
            obj.LastReport = mps.writeReport(obj.OutputDir, sourceFile, ...
                params, obj.LastRun);
            obj.ReportButton.Enable = 'on';
            obj.StatusLabel.Text = mps.tr( ...
                '自定义图已保存，HTML 报告已更新。', ...
                'Custom plot saved and the HTML report updated.');
        end

        function exportCurveCsv(obj)
            noneLabel = mps.tr('(无)', '(None)');
            if isempty(obj.OutputDir) || ~isfolder(obj.OutputDir)
                obj.alert(mps.tr('请先运行一次脚本。', ...
                    'Run a script first.'), ...
                    mps.tr('没有输出目录', 'No output folder'), ...
                    'Icon', 'warning');
                return;
            end
            xName = obj.XDrop.Value;
            if isempty(xName) || strcmp(xName, noneLabel)
                return;
            end
            yNames = obj.YList.Value;
            if ischar(yNames)
                yNames = {yNames};
            end
            if isempty(yNames) || (numel(yNames) == 1 && ...
                    strcmp(yNames{1}, noneLabel))
                return;
            end
            S = obj.loadVariables([{xName}, yNames]);
            if ~isfield(S, xName)
                obj.alert(mps.tr( ...
                    '工作区里没有可导出的变量。', ...
                    'There are no variables in the workspace to export.'), ...
                    mps.tr('没有数据', 'No data'), 'Icon', 'warning');
                return;
            end
            x = S.(xName);
            cols = {x(:)};
            names = {matlab.lang.makeValidName(xName)};
            for k = 1:numel(yNames)
                if ~isfield(S, yNames{k})
                    continue;
                end
                y = S.(yNames{k});
                if numel(y) ~= numel(x)
                    continue;
                end
                cols{end+1} = y(:); %#ok<AGROW>
                names{end+1} = matlab.lang.makeValidName(yNames{k}); %#ok<AGROW>
            end
            if numel(cols) < 2
                obj.alert(mps.tr( ...
                    'X/Y 变量长度不一致，无法导出。', ...
                    ['X and Y variables have different lengths; ' ...
                     'cannot export.']), ...
                    mps.tr('导出失败', 'Export failed'), ...
                    'Icon', 'warning');
                return;
            end
            names = matlab.lang.makeUniqueStrings(names);
            data = [cols{:}];
            csvPath = fullfile(obj.OutputDir, 'curve_data.csv');
            try
                T = array2table(data, 'VariableNames', names);
                writetable(T, csvPath, 'Encoding', 'UTF-8');
            catch err
                obj.alert(err.message, ...
                    mps.tr('导出失败', 'Export failed'), ...
                    'Icon', 'error');
                return;
            end
            obj.StatusLabel.Text = mps.tr('曲线数据已导出：%s', ...
                'Curve data exported: %s', csvPath);
            obj.alert(mps.tr('已导出 %d 行 × %d 列：\n%s', ...
                'Exported %d rows × %d columns:\n%s', ...
                size(data, 1), size(data, 2), csvPath), ...
                mps.tr('导出成功', 'Export complete'), 'Icon', 'info');
        end

        function openReport(obj)
            if isempty(obj.LastReport) || ~isfile(obj.LastReport)
                obj.alert(mps.tr( ...
                    '还没有生成报告，请先运行。', ...
                    'No report has been generated yet. Run a script first.'), ...
                    mps.tr('没有报告', 'No report'), 'Icon', 'warning');
                return;
            end
            try
                web(obj.LastReport, '-browser');
            catch
                try
                    winopen(obj.LastReport);
                catch err
                    obj.alert(err.message, ...
                        mps.tr('打开失败', 'Open failed'), ...
                        'Icon', 'error');
                end
            end
        end

        function openFolder(obj)
            if isempty(obj.OutputDir) || ~isfolder(obj.OutputDir)
                obj.alert(mps.tr( ...
                    '还没有输出目录，请先运行。', ...
                    'There is no output folder yet. Run a script first.'), ...
                    mps.tr('没有输出', 'No output'), 'Icon', 'warning');
                return;
            end
            try
                mps.openPath(obj.OutputDir);
            catch err
                obj.alert(err.message, ...
                    mps.tr('打开失败', 'Open failed'), ...
                    'Icon', 'error');
            end
        end

        function closeFigures(obj)
            if isfield(obj.LastRun, 'figureHandles')
                hs = obj.LastRun.figureHandles;
                for k = 1:numel(hs)
                    if isvalid(hs(k))
                        close(hs(k));
                    end
                end
                obj.LastRun.figureHandles = gobjects(0);
            end
            obj.StatusLabel.Text = mps.tr( ...
                '已关闭本次运行产生的图窗。', ...
                'Closed the figures created by this run.');
        end

        function matFile = workspaceMatFile(obj)
            matFile = '';
            if isfield(obj.LastRun, 'matFile')
                matFile = obj.LastRun.matFile;
            end
        end

        function S = loadVariables(obj, names)
            S = struct();
            matFile = obj.workspaceMatFile();
            if ~isempty(matFile) && isfile(matFile)
                try
                    S = load(matFile, names{:});
                    return;
                catch err
                    mps.logWarning('按需加载工作区变量', err);
                end
            end
            if isstruct(obj.LastWorkspace)
                for k = 1:numel(names)
                    if isfield(obj.LastWorkspace, names{k})
                        S.(names{k}) = obj.LastWorkspace.(names{k});
                    end
                end
            end
        end

        function alert(obj, message, title, varargin)
            if strcmp(obj.UIFigure.Visible, 'on')
                uialert(obj.UIFigure, message, title, varargin{:});
            else
                obj.StatusLabel.Text = char(message);
            end
        end
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
