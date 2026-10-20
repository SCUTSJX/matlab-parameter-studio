classdef SweepDialog < handle
%SWEEPDIALOG Modal dialog for configuring a multi-parameter sweep.
%
%   dlg = mps.SweepDialog(params, workspace);
%   uiwait(dlg.UIFigure);
%   result = dlg.Result;   % empty when cancelled
%   delete(dlg);
%
%   The user types sweep values next to the parameters they want to vary
%   (for example "1,2,4" or "1:0.5:5").  The dialog returns the selected
%   parameter indices, their value lists and, optionally, an X/Y selection
%   for an overlay chart.

    properties
        UIFigure
        Result = struct()
    end

    properties (Access = private)
        Params
        Workspace
        Table
        SearchField
        ScenarioLabel
        MaxScenariosSpinner
        OverlayCheck
        XDrop
        YList
        ParallelCheck
        StartButton
        CancelButton
        VisibleIdx = []
        SweepText = {}
        MaxScenarios = 24
    end

    methods
        function dlg = SweepDialog(params, workspace, varargin)
            visible = 'on';
            for k = 1:2:numel(varargin)
                if k + 1 > numel(varargin), break; end
                if strcmpi(char(varargin{k}), 'Visible')
                    visible = char(varargin{k+1});
                end
            end
            dlg.Params = params;
            dlg.Workspace = workspace;
            dlg.SweepText = repmat({''}, numel(params), 1);
            dlg.createUI();
            if strcmpi(visible, 'off')
                dlg.UIFigure.Visible = 'off';
            end
            dlg.refreshTable();
            dlg.UIFigure.UserData = dlg;
        end

        function delete(dlg)
            if ~isempty(dlg.UIFigure) && isvalid(dlg.UIFigure)
                delete(dlg.UIFigure);
            end
        end

        function setSweepText(dlg, paramIdx, txt)
            %SETSWEEPTEXT Programmatic sweep text (tests / automation).
            if paramIdx < 1 || paramIdx > numel(dlg.SweepText)
                return;
            end
            dlg.SweepText{paramIdx} = strtrim(char(txt));
            dlg.refreshTable();
        end

        function start(dlg)
            %START Same as clicking 开始扫描.
            dlg.onStart();
        end

        function cancel(dlg)
            %CANCEL Same as clicking 取消.
            dlg.onCancel();
        end
    end

    methods (Access = private)
        % -----------------------------------------------------------------
        function createUI(dlg)
            dlg.UIFigure = uifigure('Name', '批量扫描', ...
                'Position', [220 120 880 660]);
            try
                dlg.UIFigure.Theme = 'light';   % R2025a+
            catch
            end
            root = uigridlayout(dlg.UIFigure, [5 1]);
            root.RowHeight = {30, 30, '1x', 130, 36};
            root.Padding = [12 12 12 12];
            root.RowSpacing = 8;

            uilabel(root, 'Text', ...
                '给要扫描的参数填“扫描值”，例如 1,2,4 或 1:0.5:5；留空表示不扫描该参数。', ...
                'FontWeight', 'bold');

            top = uigridlayout(root, [1 4]);
            top.Layout.Row = 2;
            top.ColumnWidth = {220, '1x', 100, 140};
            top.Padding = [0 0 0 0];
            dlg.SearchField = uieditfield(top, 'text', ...
                'Placeholder', '搜索参数...', ...
                'ValueChangedFcn', @(s, e) dlg.refreshTable());
            dlg.SearchField.Layout.Column = 1;
            dlg.MaxScenariosSpinner = uispinner(top, ...
                'Limits', [1 500], 'Value', dlg.MaxScenarios, ...
                'Tooltip', '扫描组数上限（防止误填出几百次运行）', ...
                'ValueChangedFcn', @(s, e) dlg.updateCount());
            dlg.MaxScenariosSpinner.Layout.Column = 3;
            dlg.ScenarioLabel = uilabel(top, 'Text', '预计 0 组', ...
                'HorizontalAlignment', 'right', 'FontWeight', 'bold');
            dlg.ScenarioLabel.Layout.Column = 4;

            dlg.Table = uitable(root, ...
                'ColumnName', {'参数', '当前值', '扫描值', '说明'}, ...
                'ColumnEditable', [false false true false], ...
                'ColumnFormat', {'char', 'char', 'char', 'char'}, ...
                'ColumnWidth', {230, 110, 220, '1x'}, ...
                'RowName', [], ...
                'CellEditCallback', @(s, e) dlg.onCellEdit(e));
            dlg.Table.Layout.Row = 3;

            panel = uipanel(root, 'Title', '叠加曲线（可选）', ...
                'FontWeight', 'bold');
            panel.Layout.Row = 4;
            og = uigridlayout(panel, [2 2]);
            og.RowHeight = {26, 76};
            og.ColumnWidth = {'1x', '1x'};
            og.Padding = [8 8 8 8];
            og.RowSpacing = 4;

            dlg.OverlayCheck = uicheckbox(og, ...
                'Text', '扫描结束后叠加 X/Y 曲线，并计算指标 CSV（带图例）', ...
                'Value', false);
            dlg.OverlayCheck.Layout.Row = 1;
            dlg.OverlayCheck.Layout.Column = [1 2];

            xg = uigridlayout(og, [1 2]);
            xg.Layout.Row = 2;
            xg.Layout.Column = 1;
            xg.ColumnWidth = {50, '1x'};
            xg.Padding = [0 0 0 0];
            uilabel(xg, 'Text', 'X 轴');
            dlg.XDrop = uidropdown(xg, 'Items', {'(无)'}, 'Value', '(无)');
            dlg.XDrop.Layout.Column = 2;

            yg = uigridlayout(og, [1 2]);
            yg.Layout.Row = 2;
            yg.Layout.Column = 2;
            yg.ColumnWidth = {90, '1x'};
            yg.Padding = [0 0 0 0];
            uilabel(yg, 'Text', 'Y 轴（可多选）');
            dlg.YList = uilistbox(yg, 'Items', {'(无)'}, ...
                'Value', {'(无)'}, 'Multiselect', 'on');
            dlg.YList.Layout.Column = 2;

            buttons = uigridlayout(root, [1 3]);
            buttons.Layout.Row = 5;
            buttons.ColumnWidth = {'1x', 90, 120};
            buttons.Padding = [0 0 0 0];
            dlg.ParallelCheck = uicheckbox(buttons, ...
                'Text', '并行运行（需要 Parallel Computing Toolbox）', ...
                'Value', false);
            if ~license('test', 'Distrib_Computing_Toolbox')
                dlg.ParallelCheck.Enable = 'off';
            end
            dlg.CancelButton = uibutton(buttons, 'Text', '取消', ...
                'ButtonPushedFcn', @(s, e) dlg.onCancel());
            dlg.CancelButton.Layout.Column = 2;
            dlg.StartButton = uibutton(buttons, 'Text', '开始扫描', ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.18 0.45 0.85], ...
                'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(s, e) dlg.onStart());
            dlg.StartButton.Layout.Column = 3;

            dlg.populateWorkspaceChoices();
        end

        % -----------------------------------------------------------------
        function refreshTable(dlg)
            q = lower(strtrim(char(dlg.SearchField.Value)));
            idx = [];
            for k = 1:numel(dlg.Params)
                p = dlg.Params(k);
                keep = true;
                if ~isempty(q)
                    keep = contains(lower(sprintf('%s %s %s', ...
                        p.name, p.note, p.context)), q);
                end
                if keep
                    idx(end+1) = k; %#ok<AGROW>
                end
            end
            dlg.VisibleIdx = idx;

            data = cell(numel(idx), 4);
            for j = 1:numel(idx)
                p = dlg.Params(idx(j));
                note = p.note;
                if isempty(note)
                    note = p.context;
                end
                if numel(note) > 100
                    note = [note(1:97), '...'];
                end
                data{j,1} = p.name;
                data{j,2} = p.value;
                data{j,3} = dlg.SweepText{idx(j)};
                data{j,4} = note;
            end
            dlg.Table.Data = data;
            dlg.updateCount();
        end

        function onCellEdit(dlg, event)
            if isempty(event.Indices) || isempty(dlg.VisibleIdx)
                return;
            end
            row = event.Indices(1);
            col = event.Indices(2);
            if col ~= 3 || row < 1 || row > numel(dlg.VisibleIdx)
                return;
            end
            idx = dlg.VisibleIdx(row);
            dlg.SweepText{idx} = strtrim(char(event.NewData));
            dlg.updateCount();
        end

        function updateCount(dlg)
            if ~isempty(dlg.MaxScenariosSpinner) && ...
                    isvalid(dlg.MaxScenariosSpinner)
                dlg.MaxScenarios = round(dlg.MaxScenariosSpinner.Value);
            end
            total = 1;
            anyActive = false;
            bad = false;
            for k = 1:numel(dlg.SweepText)
                t = strtrim(dlg.SweepText{k});
                if isempty(t)
                    continue;
                end
                [v, err] = mps.parseSweepValues(t);
                if ~isempty(err) || isempty(v)
                    bad = true;
                    continue;
                end
                anyActive = true;
                total = total * numel(v);
            end
            if ~anyActive
                dlg.ScenarioLabel.Text = '预计 0 组';
                dlg.ScenarioLabel.FontColor = [0.4 0.4 0.4];
            elseif bad
                dlg.ScenarioLabel.Text = '有无法解析的扫描值';
                dlg.ScenarioLabel.FontColor = [0.8 0.1 0.1];
            elseif total > dlg.MaxScenarios
                dlg.ScenarioLabel.Text = sprintf('预计 %d 组（上限 %d）', ...
                    total, dlg.MaxScenarios);
                dlg.ScenarioLabel.FontColor = [0.8 0.1 0.1];
            else
                dlg.ScenarioLabel.Text = sprintf('预计 %d 组', total);
                dlg.ScenarioLabel.FontColor = [0.05 0.4 0.15];
            end
        end

        function populateWorkspaceChoices(dlg)
            names = {};
            if isstruct(dlg.Workspace)
                fields = fieldnames(dlg.Workspace);
                for k = 1:numel(fields)
                    v = dlg.Workspace.(fields{k});
                    if (isnumeric(v) || islogical(v)) && isvector(v) && ...
                            numel(v) >= 2 && numel(v) <= 1e6 && isreal(v)
                        names{end+1} = fields{k}; %#ok<AGROW>
                    end
                end
            end
            names = sort(names);
            if isempty(names)
                dlg.OverlayCheck.Value = false;
                dlg.OverlayCheck.Enable = 'off';
                dlg.XDrop.Items = {'(无)'};
                dlg.XDrop.Value = '(无)';
                dlg.YList.Items = {'(无)'};
                dlg.YList.Value = {'(无)'};
                return;
            end
            dlg.XDrop.Items = names;
            if any(strcmp(names, 't'))
                dlg.XDrop.Value = 't';
            else
                dlg.XDrop.Value = names{1};
            end
            ys = names(~strcmp(names, dlg.XDrop.Value));
            if isempty(ys)
                ys = names;
            end
            dlg.YList.Items = ys;
            dlg.YList.Value = ys(1:min(2, numel(ys)));
        end

        function onStart(dlg)
            activeIdx = [];
            values = {};
            for k = 1:numel(dlg.SweepText)
                t = strtrim(dlg.SweepText{k});
                if isempty(t)
                    continue;
                end
                [v, err] = mps.parseSweepValues(t);
                if ~isempty(err) || isempty(v)
                    uialert(dlg.UIFigure, sprintf( ...
                        '参数 %s 的扫描值无法解析：%s', ...
                        dlg.Params(k).name, t), ...
                        '扫描值错误', 'Icon', 'error');
                    return;
                end
                activeIdx(end+1) = k; %#ok<AGROW>
                values{end+1} = v; %#ok<AGROW>
            end
            if isempty(activeIdx)
                uialert(dlg.UIFigure, '请至少给一个参数填写扫描值。', ...
                    '没有扫描参数', 'Icon', 'warning');
                return;
            end

            names = {dlg.Params(activeIdx).name};
            try
                scenarios = mps.sweepScenarios(names, values, dlg.MaxScenarios);
            catch err
                uialert(dlg.UIFigure, err.message, '组合太多', ...
                    'Icon', 'warning');
                return;
            end

            overlay = false;
            xName = '';
            yNames = {};
            if dlg.OverlayCheck.Value && strcmp(dlg.OverlayCheck.Enable, 'on')
                xName = dlg.XDrop.Value;
                yNames = dlg.YList.Value;
                if ischar(yNames)
                    yNames = {yNames};
                end
                if ~isempty(xName) && ~strcmp(xName, '(无)') && ...
                        ~isempty(yNames) && ...
                        ~(numel(yNames) == 1 && strcmp(yNames{1}, '(无)'))
                    overlay = true;
                end
            end

            dlg.Result = struct('activeIdx', activeIdx, ...
                'values', {values}, 'scenarios', scenarios, ...
                'overlay', overlay, 'xName', xName, 'yNames', {yNames}, ...
                'parallel', logical(dlg.ParallelCheck.Value), ...
                'maxScenarios', dlg.MaxScenarios);
            delete(dlg.UIFigure);
        end

        function onCancel(dlg)
            dlg.Result = struct();
            delete(dlg.UIFigure);
        end
    end
end
