classdef RunHistoryDialog < handle
%RUNHISTORYDIALOG Browse past runs, compare any two, load their parameters.
%
%   dlg = mps.RunHistoryDialog(root, 'SourceFile', file, ...
%                              'CurrentOutDir', currentOutDir);
%   uiwait(dlg.UIFigure);
%   result = dlg.Result;   % empty unless the user pressed 载入参数
%   delete(dlg);
%
%   Result (only for the load action):
%       action  - 'load'
%       runPath - folder of the selected run
%       values  - struct array accepted by mps.applyPreset
%       meta    - run.json record when available

    properties
        UIFigure
        Result = struct()
    end

    properties (Access = private)
        Root = ''
        SourceFile = ''
        CurrentOutDir = ''
        Runs = struct([])
        Table
        HeaderLabel
        StatusLabel
        ALabel
        BLabel
        OpenReportButton
        OpenFolderButton
        LoadButton
        DeleteButton
        SetAButton
        SetBButton
        CompareButton
        CleanButton
        SelectedRun = 0
        AIndex = 0
        BIndex = 0
    end

    methods
        function dlg = RunHistoryDialog(root, varargin)
            visible = 'on';
            for k = 1:2:numel(varargin)
                if k + 1 > numel(varargin), break; end
                switch lower(char(varargin{k}))
                    case 'visible'
                        visible = char(varargin{k+1});
                    case 'sourcefile'
                        dlg.SourceFile = char(varargin{k+1});
                    case 'currentoutdir'
                        dlg.CurrentOutDir = char(varargin{k+1});
                end
            end
            dlg.Root = char(root);
            dlg.createUI();
            dlg.refresh();
            dlg.UIFigure.UserData = dlg;
            dlg.UIFigure.Visible = visible;
        end

        function delete(dlg)
            if ~isempty(dlg.UIFigure) && isvalid(dlg.UIFigure)
                delete(dlg.UIFigure);
            end
        end

        function n = runCount(dlg)
            %RUNCOUNT Number of runs shown in the table.
            n = numel(dlg.Runs);
        end

        function refresh(dlg)
            %REFRESH Re-scan the run folder and rebuild the table.
            dlg.Runs = mps.listRuns(dlg.Root, 'SourceFile', dlg.SourceFile);
            if isempty(dlg.Runs)
                dlg.Table.Data = cell(0, 8);
                dlg.SelectedRun = 0;
                dlg.HeaderLabel.Text = mps.tr('%s · 0 次运行', ...
                    '%s · 0 runs', dlg.Root);
            else
                data = cell(numel(dlg.Runs), 8);
                totalBytes = 0;
                for k = 1:numel(dlg.Runs)
                    r = dlg.Runs(k);
                    totalBytes = totalBytes + r.bytes;
                    data{k,1} = r.created;
                    if r.isSweep
                        data{k,2} = mps.tr('批量扫描', 'Batch sweep');
                    else
                        data{k,2} = mps.tr('单次运行', 'Single run');
                    end
                    data{k,3} = statusText(r.ok);
                    data{k,4} = r.paramSummary;
                    if isnan(r.elapsed)
                        data{k,5} = '-';
                    else
                        data{k,5} = sprintf('%.2f', r.elapsed);
                    end
                    data{k,6} = r.figureCount;
                    data{k,7} = fmtBytes(r.bytes);
                    data{k,8} = r.name;
                end
                dlg.Table.Data = data;
                dlg.HeaderLabel.Text = mps.tr('%s · %d 次运行 · %s', ...
                    '%s · %d runs · %s', ...
                    dlg.Root, numel(dlg.Runs), fmtBytes(totalBytes));
                dlg.SelectedRun = 1;
                try
                    dlg.Table.Selection = [1 1];
                catch err
                    mps.logWarning('设置运行历史默认选中行', err, 'Silent', true);
                end
            end
            dlg.chooseDefaults();
            dlg.updateABLabels();
            dlg.updateStatus();
            dlg.updateButtons();
        end
    end

    methods (Access = private)
        % -----------------------------------------------------------------
        function createUI(dlg)
            dlg.UIFigure = uifigure('Name', ...
                mps.tr('运行历史', 'Run history'), ...
                'Position', [240 140 1000 620], 'Visible', 'off');
            try
                dlg.UIFigure.Theme = 'light';   % R2025a+
            catch err
                mps.logWarning('设置运行历史窗口主题', err, 'Silent', true);
            end
            dlg.UIFigure.CloseRequestFcn = @(s, e) dlg.delete();

            root = uigridlayout(dlg.UIFigure, [5 1]);
            root.RowHeight = {24, '1x', 22, 22, 89};
            root.Padding = [12 12 12 12];
            root.RowSpacing = 8;

            header = uigridlayout(root, [1 2]);
            header.Layout.Row = 1;
            header.ColumnWidth = {'1x', 80};
            header.Padding = [0 0 0 0];
            dlg.HeaderLabel = uilabel(header, 'Text', dlg.Root, ...
                'FontColor', [0.35 0.35 0.35], 'Interpreter', 'none');
            refreshButton = uibutton(header, ...
                'Text', mps.tr('刷新', 'Refresh'), ...
                'ButtonPushedFcn', @(s, e) dlg.refresh());
            refreshButton.Layout.Column = 2;

            dlg.Table = uitable(root, ...
                'ColumnName', {mps.tr('时间', 'Time'), ...
                mps.tr('类型', 'Type'), ...
                mps.tr('状态', 'Status'), ...
                mps.tr('参数变化', 'Parameter changes'), ...
                mps.tr('耗时 (s)', 'Elapsed (s)'), ...
                mps.tr('图', 'Figures'), ...
                mps.tr('大小', 'Size'), ...
                mps.tr('目录', 'Folder')}, ...
                'ColumnEditable', false, ...
                'ColumnWidth', {136, 72, 52, '1x', 62, 32, 64, 150}, ...
                'RowName', [], ...
                'CellSelectionCallback', @(s, e) dlg.onTableSelect(e));
            dlg.Table.Layout.Row = 2;
            try
                dlg.Table.Multiselect = 'off';
            catch err
                mps.logWarning('关闭运行历史表多选', err, 'Silent', true);
            end
            try
                dlg.Table.DoubleClickedFcn = @(s, e) dlg.onOpenReport();
            catch err
                mps.logWarning('设置运行历史表双击回调', err, 'Silent', true);
            end

            dlg.StatusLabel = uilabel(root, 'Text', '', ...
                'FontColor', [0.35 0.35 0.35], 'Interpreter', 'none');
            dlg.StatusLabel.Layout.Row = 3;

            ab = uigridlayout(root, [1 2]);
            ab.Layout.Row = 4;
            ab.ColumnWidth = {'1x', '1x'};
            ab.Padding = [0 0 0 0];
            dlg.ALabel = uilabel(ab, ...
                'Text', mps.tr('A（基准）: 未选择', 'A (baseline): none'));
            dlg.BLabel = uilabel(ab, ...
                'Text', mps.tr('B（当前）: 未选择', 'B (current): none'));
            dlg.BLabel.Layout.Column = 2;

            actions = uigridlayout(root, [3 4]);
            actions.Layout.Row = 5;
            actions.RowHeight = {26, 26, 26};
            actions.ColumnWidth = {'1x', '1x', '1x', '1x'};
            actions.Padding = [0 0 0 0];
            actions.RowSpacing = 5;
            actions.ColumnSpacing = 6;

            dlg.OpenReportButton = uibutton(actions, ...
                'Text', mps.tr('打开报告', 'Open report'), ...
                'ButtonPushedFcn', @(s, e) dlg.onOpenReport());
            dlg.OpenFolderButton = uibutton(actions, ...
                'Text', mps.tr('打开文件夹', 'Open folder'), ...
                'ButtonPushedFcn', @(s, e) dlg.onOpenFolder());
            dlg.LoadButton = uibutton(actions, ...
                'Text', mps.tr('载入参数', 'Load parameters'), ...
                'ButtonPushedFcn', @(s, e) dlg.onLoad());
            dlg.DeleteButton = uibutton(actions, ...
                'Text', mps.tr('删除运行', 'Delete run'), ...
                'ButtonPushedFcn', @(s, e) dlg.onDelete());
            dlg.SetAButton = uibutton(actions, ...
                'Text', mps.tr('设为基准 A', 'Set as baseline A'), ...
                'ButtonPushedFcn', @(s, e) dlg.onSetAB('a'));
            dlg.SetBButton = uibutton(actions, ...
                'Text', mps.tr('设为当前 B', 'Set as current B'), ...
                'ButtonPushedFcn', @(s, e) dlg.onSetAB('b'));
            dlg.CompareButton = uibutton(actions, ...
                'Text', mps.tr('对比 A / B', 'Compare A / B'), ...
                'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(s, e) dlg.onCompare());
            uibutton(actions, 'Text', mps.tr('关闭', 'Close'), ...
                'ButtonPushedFcn', @(s, e) dlg.delete());
            dlg.CleanButton = uibutton(actions, ...
                'Text', mps.tr('清理旧运行...', 'Clean up old runs...'), ...
                'ButtonPushedFcn', @(s, e) dlg.onClean());
            dlg.CleanButton.Layout.Row = 3;
            dlg.CleanButton.Layout.Column = 1;
        end

        % -----------------------------------------------------------------
        function onTableSelect(dlg, event)
            rows = [];
            try
                selection = dlg.Table.Selection;
                if ~isempty(selection)
                    rows = unique(selection(:, 1));
                end
            catch err
                mps.logWarning('读取运行历史选中行', err, 'Silent', true);
            end
            if isempty(rows) && isstruct(event) && isfield(event, 'Indices') ...
                    && ~isempty(event.Indices)
                rows = unique(event.Indices(:, 1));
            end
            rows = rows(rows >= 1 & rows <= numel(dlg.Runs));
            if isempty(rows)
                dlg.SelectedRun = 0;
            else
                dlg.SelectedRun = rows(end);
            end
            dlg.updateStatus();
            dlg.updateButtons();
        end

        % -----------------------------------------------------------------
        function chooseDefaults(dlg)
            aPath = dlg.pathOf(dlg.AIndex);
            bPath = dlg.pathOf(dlg.BIndex);
            dlg.AIndex = dlg.findPath(aPath);
            dlg.BIndex = dlg.findPath(bPath);

            if dlg.BIndex == 0
                if ~isempty(dlg.CurrentOutDir)
                    dlg.BIndex = dlg.findPath(dlg.CurrentOutDir);
                end
                if dlg.BIndex == 0 && ~isempty(dlg.Runs)
                    dlg.BIndex = 1;
                end
            end
            if dlg.AIndex == 0
                for k = 1:numel(dlg.Runs)
                    if k ~= dlg.BIndex
                        dlg.AIndex = k;
                        break;
                    end
                end
            end
            if dlg.AIndex == dlg.BIndex
                dlg.AIndex = 0;
            end
        end

        % -----------------------------------------------------------------
        function path = pathOf(dlg, index)
            path = '';
            if index >= 1 && index <= numel(dlg.Runs)
                path = dlg.Runs(index).path;
            end
        end

        % -----------------------------------------------------------------
        function index = findPath(dlg, path)
            index = 0;
            if isempty(path)
                return;
            end
            for k = 1:numel(dlg.Runs)
                if strcmpi(dlg.Runs(k).path, path)
                    index = k;
                    return;
                end
            end
        end

        % -----------------------------------------------------------------
        function run = selectedRun(dlg)
            run = [];
            if dlg.SelectedRun >= 1 && dlg.SelectedRun <= numel(dlg.Runs)
                run = dlg.Runs(dlg.SelectedRun);
            end
        end

        % -----------------------------------------------------------------
        function updateStatus(dlg)
            if isempty(dlg.Runs)
                dlg.StatusLabel.Text = mps.tr( ...
                    '还没有运行记录（%s）。先运行一次脚本，或点“刷新”。', ...
                    'No runs yet (%s). Run a script first, or click "Refresh".', ...
                    dlg.Root);
                return;
            end
            run = dlg.selectedRun();
            if isempty(run)
                dlg.StatusLabel.Text = mps.tr( ...
                    '选中一行后可以打开报告、载入参数或设为 A/B。', ...
                    'Select a row to open its report, load its parameters, or set A/B.');
            else
                dlg.StatusLabel.Text = sprintf('%s · %s', ...
                    run.created, run.path);
            end
        end

        % -----------------------------------------------------------------
        function updateABLabels(dlg)
            aName = dlg.runName(dlg.AIndex);
            bName = dlg.runName(dlg.BIndex);
            dlg.ALabel.Text = mps.tr('A（基准）: %s', ...
                'A (baseline): %s', aName);
            dlg.BLabel.Text = mps.tr('B（当前）: %s', ...
                'B (current): %s', bName);
        end

        % -----------------------------------------------------------------
        function name = runName(dlg, index)
            if index >= 1 && index <= numel(dlg.Runs)
                name = dlg.Runs(index).name;
            else
                name = mps.tr('未选择', 'none');
            end
        end

        % -----------------------------------------------------------------
        function updateButtons(dlg)
            run = dlg.selectedRun();
            if isempty(run)
                dlg.OpenReportButton.Enable = 'off';
                dlg.OpenFolderButton.Enable = 'off';
                dlg.LoadButton.Enable = 'off';
                dlg.DeleteButton.Enable = 'off';
                dlg.SetAButton.Enable = 'off';
                dlg.SetBButton.Enable = 'off';
            else
                if isempty(run.reportPath)
                    dlg.OpenReportButton.Enable = 'off';
                else
                    dlg.OpenReportButton.Enable = 'on';
                end
                dlg.OpenFolderButton.Enable = 'on';
                if run.canLoad
                    dlg.LoadButton.Enable = 'on';
                else
                    dlg.LoadButton.Enable = 'off';
                end
                if strcmpi(run.path, dlg.CurrentOutDir)
                    dlg.DeleteButton.Enable = 'off';
                else
                    dlg.DeleteButton.Enable = 'on';
                end
                dlg.SetAButton.Enable = 'on';
                dlg.SetBButton.Enable = 'on';
            end

            canCompare = dlg.AIndex >= 1 && dlg.BIndex >= 1 && ...
                dlg.AIndex ~= dlg.BIndex && ...
                dlg.AIndex <= numel(dlg.Runs) && ...
                dlg.BIndex <= numel(dlg.Runs) && ...
                dlg.Runs(dlg.AIndex).canCompare && ...
                dlg.Runs(dlg.BIndex).canCompare;
            if canCompare
                dlg.CompareButton.Enable = 'on';
            else
                dlg.CompareButton.Enable = 'off';
            end
            if numel(dlg.Runs) >= 2
                dlg.CleanButton.Enable = 'on';
            else
                dlg.CleanButton.Enable = 'off';
            end
        end

        % -----------------------------------------------------------------
        function onClean(dlg)
            if numel(dlg.Runs) < 2
                return;
            end
            keep10 = mps.tr('保留最近 10 次', 'Keep latest 10');
            keep30 = mps.tr('保留最近 30 次', 'Keep latest 30');
            choice = uiconfirm(dlg.UIFigure, ...
                mps.tr(['保留最近的运行，删除更早的结果' ...
                '（当前正在使用的运行不会被删除）。'], ...
                ['Keep recent runs and delete older results ' ...
                 '(the run currently in use is never deleted).']), ...
                mps.tr('清理旧运行', 'Clean up old runs'), ...
                'Options', {keep10, keep30, mps.tr('取消', 'Cancel')}, ...
                'DefaultOption', 3, 'CancelOption', 3);
            switch choice
                case keep10
                    keepN = 10;
                case keep30
                    keepN = 30;
                otherwise
                    return;
            end
            if numel(dlg.Runs) <= keepN
                dlg.StatusLabel.Text = mps.tr( ...
                    '当前只有 %d 次运行，不需要清理。', ...
                    'Only %d runs exist; nothing to clean up.', ...
                    numel(dlg.Runs));
                return;
            end
            removeIdx = (keepN + 1):numel(dlg.Runs);
            removeIdx = removeIdx(~strcmpi({dlg.Runs(removeIdx).path}, ...
                dlg.CurrentOutDir));
            if isempty(removeIdx)
                return;
            end
            confirm = uiconfirm(dlg.UIFigure, mps.tr( ...
                '将删除 %d 次旧运行，保留最近 %d 次。是否继续？', ...
                'Delete %d old runs and keep the latest %d. Continue?', ...
                numel(removeIdx), keepN), ...
                mps.tr('确认清理', 'Confirm cleanup'), ...
                'Options', {mps.tr('删除', 'Delete'), ...
                mps.tr('取消', 'Cancel')}, ...
                'DefaultOption', 2, 'CancelOption', 2);
            if ~strcmp(confirm, mps.tr('删除', 'Delete'))
                return;
            end
            failed = 0;
            for k = removeIdx
                try
                    rmdir(dlg.Runs(k).path, 's');
                catch err
                    failed = failed + 1;
                    mps.logWarning(sprintf('删除旧运行 %s', ...
                        dlg.Runs(k).name), err);
                end
            end
            dlg.refresh();
            if failed > 0
                dlg.StatusLabel.Text = mps.tr( ...
                    '已删除旧运行，%d 个文件夹删除失败。', ...
                    'Old runs deleted, but %d folders could not be removed.', ...
                    failed);
            else
                dlg.StatusLabel.Text = mps.tr( ...
                    '已删除 %d 次旧运行。', ...
                    'Deleted %d old runs.', numel(removeIdx));
            end
        end

        % -----------------------------------------------------------------
        function onSetAB(dlg, which)
            run = dlg.selectedRun();
            if isempty(run)
                uialert(dlg.UIFigure, ...
                    mps.tr('请先在列表里选中一行。', ...
                    'Select a row in the list first.'), ...
                    mps.tr('没有选中运行', 'No run selected'), ...
                    'Icon', 'warning');
                return;
            end
            if strcmp(which, 'a')
                dlg.AIndex = dlg.SelectedRun;
            else
                dlg.BIndex = dlg.SelectedRun;
            end
            dlg.updateABLabels();
            dlg.updateButtons();
        end

        % -----------------------------------------------------------------
        function onOpenReport(dlg)
            run = dlg.selectedRun();
            if isempty(run) || isempty(run.reportPath) || ...
                    ~isfile(run.reportPath)
                uialert(dlg.UIFigure, ...
                    mps.tr('这次运行没有 HTML 报告。', ...
                    'This run has no HTML report.'), ...
                    mps.tr('没有报告', 'No report'), 'Icon', 'warning');
                return;
            end
            try
                web(run.reportPath, '-browser');
            catch
                try
                    mps.openPath(run.reportPath);
                catch err
                    uialert(dlg.UIFigure, err.message, ...
                        mps.tr('打开失败', 'Open failed'), 'Icon', 'error');
                end
            end
        end

        % -----------------------------------------------------------------
        function onOpenFolder(dlg)
            run = dlg.selectedRun();
            if isempty(run)
                return;
            end
            try
                mps.openPath(run.path);
            catch err
                uialert(dlg.UIFigure, err.message, ...
                    mps.tr('打开失败', 'Open failed'), 'Icon', 'error');
            end
        end

        % -----------------------------------------------------------------
        function onLoad(dlg)
            run = dlg.selectedRun();
            if isempty(run) || ~run.canLoad
                uialert(dlg.UIFigure, ...
                    mps.tr(['这次运行没有保存完整参数，无法载入。' ...
                     '（批量扫描请打开报告查看每组结果。）'], ...
                    ['This run did not save complete parameters and cannot be ' ...
                     'loaded. (For batch sweeps, open the report to see each scenario.)']), ...
                    mps.tr('无法载入', 'Cannot load'), 'Icon', 'warning');
                return;
            end
            try
                [values, meta] = mps.loadRunParameters(run.path);
            catch err
                uialert(dlg.UIFigure, err.message, ...
                    mps.tr('载入失败', 'Load failed'), ...
                    'Icon', 'error');
                return;
            end
            dlg.Result = struct('action', 'load', 'runPath', run.path, ...
                'values', {values}, 'meta', meta);
            if ~isempty(dlg.UIFigure) && isvalid(dlg.UIFigure)
                delete(dlg.UIFigure);
            end
        end

        % -----------------------------------------------------------------
        function onDelete(dlg)
            run = dlg.selectedRun();
            if isempty(run)
                return;
            end
            if strcmpi(run.path, dlg.CurrentOutDir)
                uialert(dlg.UIFigure, ...
                    mps.tr(['这是本次运行的结果，正在界面里使用，不能删除。'], ...
                    ['This is the result of the current run and is in use; ' ...
                     'it cannot be deleted.']), ...
                    mps.tr('不能删除本次运行', 'Cannot delete the current run'), ...
                    'Icon', 'warning');
                return;
            end
            choice = uiconfirm(dlg.UIFigure, ...
                mps.tr('删除这次运行的整个文件夹？\n\n%s', ...
                'Delete the entire folder for this run?\n\n%s', run.path), ...
                mps.tr('删除运行', 'Delete run'), ...
                'Options', {mps.tr('删除', 'Delete'), ...
                mps.tr('取消', 'Cancel')}, ...
                'DefaultOption', 2, 'CancelOption', 2);
            if ~strcmp(choice, mps.tr('删除', 'Delete'))
                return;
            end
            try
                rmdir(run.path, 's');
            catch err
                uialert(dlg.UIFigure, err.message, ...
                    mps.tr('删除失败', 'Delete failed'), ...
                    'Icon', 'error');
                return;
            end
            if dlg.AIndex == dlg.SelectedRun
                dlg.AIndex = 0;
            end
            if dlg.BIndex == dlg.SelectedRun
                dlg.BIndex = 0;
            end
            if dlg.AIndex > dlg.SelectedRun
                dlg.AIndex = dlg.AIndex - 1;
            end
            if dlg.BIndex > dlg.SelectedRun
                dlg.BIndex = dlg.BIndex - 1;
            end
            dlg.refresh();
        end

        % -----------------------------------------------------------------
        function onCompare(dlg)
            if dlg.AIndex < 1 || dlg.BIndex < 1 || ...
                    dlg.AIndex > numel(dlg.Runs) || ...
                    dlg.BIndex > numel(dlg.Runs)
                uialert(dlg.UIFigure, ...
                    mps.tr(['请先选中两次运行，' ...
                    '分别点“设为基准 A / 设为当前 B”。'], ...
                    ['Select two runs and click "Set as baseline A" / ' ...
                     '"Set as current B" for each.']), ...
                    mps.tr('没有选择运行', 'No runs selected'), ...
                    'Icon', 'warning');
                return;
            end
            if dlg.AIndex == dlg.BIndex
                uialert(dlg.UIFigure, ...
                    mps.tr('A 和 B 是同一次运行。', ...
                    'A and B are the same run.'), ...
                    mps.tr('没有区分', 'No difference'), ...
                    'Icon', 'warning');
                return;
            end
            runA = dlg.Runs(dlg.AIndex);
            runB = dlg.Runs(dlg.BIndex);
            if ~runA.canCompare || ~runB.canCompare
                uialert(dlg.UIFigure, ...
                    mps.tr(['选中的运行缺少参数或工作区记录。' ...
                     '批量扫描目录请打开报告查看每组结果；' ...
                     '单次运行目录才支持 A/B 对比。'], ...
                    ['The selected runs are missing parameters or workspace ' ...
                     'records. For batch sweep folders, open the report to see ' ...
                     'each scenario; A/B comparison works only for single-run folders.']), ...
                    mps.tr('无法对比', 'Cannot compare'), 'Icon', 'warning');
                return;
            end
            target = fullfile(runB.path, 'compare.html');
            try
                mps.compareRuns(runA.path, runB.path, target);
            catch err
                uialert(dlg.UIFigure, err.message, ...
                    mps.tr('对比失败', 'Compare failed'), ...
                    'Icon', 'error');
                return;
            end
            dlg.StatusLabel.Text = mps.tr( ...
                '对比报告已生成：%s', ...
                'Comparison report created: %s', target);
            try
                web(target, '-browser');
            catch
                try
                    mps.openPath(target);
                catch err
                    mps.logWarning('打开对比报告', err);
                end
            end
        end
    end
end

% -------------------------------------------------------------------------
function s = statusText(ok)
    if isnan(ok)
        s = mps.tr('未知', 'Unknown');
    elseif logical(ok)
        s = mps.tr('成功', 'Success');
    else
        s = mps.tr('失败', 'Failed');
    end
end

% -------------------------------------------------------------------------
function s = fmtBytes(bytes)
    if isempty(bytes) || isnan(bytes)
        s = '-';
    elseif bytes >= 1024^3
        s = sprintf('%.2f GB', bytes / 1024^3);
    elseif bytes >= 1024^2
        s = sprintf('%.1f MB', bytes / 1024^2);
    elseif bytes >= 1024
        s = sprintf('%.0f KB', bytes / 1024);
    else
        s = sprintf('%d B', bytes);
    end
end
