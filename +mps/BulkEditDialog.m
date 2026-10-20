classdef BulkEditDialog < handle
%BULKEDITDIALOG Configure one batch operation for the parameter table.
%
%   dlg = mps.BulkEditDialog(params, selectedIdx, visibleIdx);
%   uiwait(dlg.UIFigure);
%   result = dlg.Result;   % empty when cancelled
%   delete(dlg);
%
%   Result fields:
%       indices - parameter indices the operation applies to
%       op      - set | scale | offset | reset | useon | useoff | lock |
%                 unlock | paste
%       value   - operand text for set/scale/offset
%       values  - cell array of pasted expressions (op = paste)

    properties
        UIFigure
        Result = struct()
    end

    properties (Access = private)
        Params
        SelectedIdx = []
        VisibleIdx = []
        ScopeDrop
        OpDrop
        ValueLabel
        ValueField
        HintLabel
        CountLabel
        ApplyButton
    end

    properties (Constant, Access = private)
        ScopeKeys = {'selected', 'visible', 'all'};
        OpKeys = {'set', 'scale', 'offset', 'reset', 'useon', ...
            'useoff', 'lock', 'unlock', 'paste'};
    end

    methods
        function dlg = BulkEditDialog(params, selectedIdx, visibleIdx, varargin)
            visible = 'on';
            for k = 1:2:numel(varargin)
                if k + 1 > numel(varargin), break; end
                if strcmpi(char(varargin{k}), 'Visible')
                    visible = char(varargin{k+1});
                end
            end
            dlg.Params = params;
            dlg.SelectedIdx = double(selectedIdx(:)');
            dlg.VisibleIdx = double(visibleIdx(:)');
            dlg.createUI();
            dlg.refreshScopeItems();
            dlg.updateUI();
            dlg.UIFigure.UserData = dlg;
            dlg.UIFigure.Visible = visible;
        end

        function delete(dlg)
            if ~isempty(dlg.UIFigure) && isvalid(dlg.UIFigure)
                delete(dlg.UIFigure);
            end
        end

        function setScope(dlg, scope)
            %SETSCOPE 'selected' | 'visible' | 'all' (or the shown label).
            key = lower(strtrim(char(scope)));
            idx = find(strcmp(dlg.ScopeKeys, key), 1);
            if isempty(idx)
                idx = find(strcmp(dlg.ScopeDrop.Items, char(scope)), 1);
            end
            if isempty(idx)
                return;
            end
            if numel(dlg.ScopeDrop.Items) >= idx
                dlg.ScopeDrop.Value = dlg.ScopeDrop.Items{idx};
                dlg.updateUI();
            end
        end

        function setOperation(dlg, op)
            %SETOPERATION Key (e.g. 'scale') or the shown Chinese label.
            key = lower(strtrim(char(op)));
            idx = find(strcmp(dlg.OpKeys, key), 1);
            if isempty(idx)
                idx = find(strcmp(dlg.OpDrop.Items, char(op)), 1);
            end
            if isempty(idx)
                return;
            end
            dlg.OpDrop.Value = dlg.OpDrop.Items{idx};
            dlg.updateUI();
        end

        function setValue(dlg, value)
            %SETVALUE Programmatic operand (tests / automation).
            dlg.ValueField.Value = char(value);
            dlg.updateUI();
        end

        function apply(dlg)
            dlg.onApply();
        end

        function cancel(dlg)
            dlg.Result = struct();
            if ~isempty(dlg.UIFigure) && isvalid(dlg.UIFigure)
                delete(dlg.UIFigure);
            end
        end
    end

    methods (Access = private)
        % -----------------------------------------------------------------
        function createUI(dlg)
            dlg.UIFigure = uifigure('Name', ...
                mps.tr('批量修改参数', 'Bulk edit parameters'), ...
                'Position', [320 220 640 380], 'Visible', 'off');
            try
                dlg.UIFigure.Theme = 'light';   % R2025a+
            catch err
                mps.logWarning('设置批量修改窗口主题', err, 'Silent', true);
            end
            dlg.UIFigure.CloseRequestFcn = @(s, e) dlg.cancel();

            root = uigridlayout(dlg.UIFigure, [6 1]);
            root.RowHeight = {26, 32, 32, 32, '1x', 36};
            root.Padding = [14 14 14 14];
            root.RowSpacing = 8;

            uilabel(root, 'Text', ...
                mps.tr(['对多个参数执行同一种操作。' ...
                '先在参数表里用 Ctrl/Shift 多选行。'], ...
                ['Apply one operation to many parameters. ' ...
                 'Select rows in the parameter table with Ctrl/Shift first.']), ...
                'FontWeight', 'bold');

            scopeLabels = {mps.tr('选中行', 'Selected rows'), ...
                mps.tr('当前筛选结果', 'Filtered rows'), ...
                mps.tr('全部参数', 'All parameters')};
            scopeGrid = uigridlayout(root, [1 2]);
            scopeGrid.Layout.Row = 2;
            scopeGrid.ColumnWidth = {70, '1x'};
            scopeGrid.Padding = [0 0 0 0];
            uilabel(scopeGrid, 'Text', mps.tr('范围', 'Scope'));
            dlg.ScopeDrop = uidropdown(scopeGrid, ...
                'Items', scopeLabels, ...
                'Value', scopeLabels{1}, ...
                'ValueChangedFcn', @(s, e) dlg.updateUI());
            dlg.ScopeDrop.Layout.Column = 2;

            opGrid = uigridlayout(root, [1 2]);
            opGrid.Layout.Row = 3;
            opGrid.ColumnWidth = {70, '1x'};
            opGrid.Padding = [0 0 0 0];
            uilabel(opGrid, 'Text', mps.tr('操作', 'Operation'));
            opLabels = dlg.opLabels();
            dlg.OpDrop = uidropdown(opGrid, 'Items', opLabels, ...
                'Value', opLabels{1}, ...
                'ValueChangedFcn', @(s, e) dlg.updateUI());
            dlg.OpDrop.Layout.Column = 2;

            valueGrid = uigridlayout(root, [1 2]);
            valueGrid.Layout.Row = 4;
            valueGrid.ColumnWidth = {70, '1x'};
            valueGrid.Padding = [0 0 0 0];
            dlg.ValueLabel = uilabel(valueGrid, ...
                'Text', mps.tr('新值', 'New value'));
            dlg.ValueField = uieditfield(valueGrid, 'text', ...
                'Placeholder', mps.tr('例如 2、2*pi、[1 2 3]、1:0.1:10', ...
                'e.g. 2, 2*pi, [1 2 3], 1:0.1:10'));
            dlg.ValueField.Layout.Column = 2;
            dlg.ValueField.ValueChangedFcn = @(s, e) dlg.updateUI();

            info = uigridlayout(root, [2 1]);
            info.Layout.Row = 5;
            info.RowHeight = {22, '1x'};
            info.Padding = [0 0 0 0];
            dlg.CountLabel = uilabel(info, ...
                'Text', mps.tr('目标 0 个参数', '0 target parameters'), ...
                'FontWeight', 'bold');
            dlg.HintLabel = uilabel(info, 'Text', '', ...
                'FontColor', [0.35 0.35 0.35], 'VerticalAlignment', 'top');
            dlg.HintLabel.Layout.Row = 2;

            buttons = uigridlayout(root, [1 3]);
            buttons.Layout.Row = 6;
            buttons.ColumnWidth = {'1x', 90, 120};
            buttons.Padding = [0 0 0 0];
            uibutton(buttons, 'Text', mps.tr('取消', 'Cancel'), ...
                'ButtonPushedFcn', @(s, e) dlg.cancel());
            dlg.ApplyButton = uibutton(buttons, ...
                'Text', mps.tr('应用', 'Apply'), ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.18 0.45 0.85], ...
                'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(s, e) dlg.onApply());
            dlg.ApplyButton.Layout.Column = 3;
        end

        % -----------------------------------------------------------------
        function refreshScopeItems(dlg)
            items = { ...
                mps.tr('选中行 (%d)', 'Selected rows (%d)', ...
                numel(dlg.SelectedIdx)), ...
                mps.tr('当前筛选结果 (%d)', 'Filtered rows (%d)', ...
                numel(dlg.VisibleIdx)), ...
                mps.tr('全部参数 (%d)', 'All parameters (%d)', ...
                numel(dlg.Params))};
            dlg.ScopeDrop.Items = items;
            if isempty(dlg.SelectedIdx)
                if isempty(dlg.VisibleIdx)
                    dlg.ScopeDrop.Value = items{3};
                else
                    dlg.ScopeDrop.Value = items{2};
                end
            else
                dlg.ScopeDrop.Value = items{1};
            end
        end

        % -----------------------------------------------------------------
        function updateUI(dlg)
            indices = dlg.targetIndices();
            n = numel(indices);
            locked = 0;
            if n > 0
                locked = sum(logical([dlg.Params(indices).locked]));
            end
            dlg.CountLabel.Text = mps.tr('目标 %d 个参数（已锁定 %d）', ...
                '%d target parameters (%d locked)', n, locked);
            dlg.ApplyButton.Enable = 'on';
            if n == 0
                dlg.ApplyButton.Enable = 'off';
            end

            op = dlg.operationKey();
            switch op
                case 'set'
                    dlg.ValueLabel.Text = mps.tr('新值', 'New value');
                    dlg.ValueField.Enable = 'on';
                    dlg.ValueField.Placeholder = mps.tr( ...
                        '例如 2、2*pi、[1 2 3]、1:0.1:10', ...
                        'e.g. 2, 2*pi, [1 2 3], 1:0.1:10');
                    dlg.HintLabel.Text = dlg.lockHint( ...
                        mps.tr('把目标参数的新值设为上面的表达式。', ...
                        'Set the new value of each target to the expression above.'), ...
                        locked);
                case 'scale'
                    dlg.ValueLabel.Text = mps.tr('乘数', 'Multiplier');
                    dlg.ValueField.Enable = 'on';
                    dlg.ValueField.Placeholder = mps.tr( ...
                        '例如 2、0.5、pi/2', 'e.g. 2, 0.5, pi/2');
                    dlg.HintLabel.Text = dlg.lockHint( ...
                        mps.tr('新值 = 当前新值 × 乘数。', ...
                        'New value = current new value × multiplier.'), locked);
                case 'offset'
                    dlg.ValueLabel.Text = mps.tr('偏移量', 'Offset');
                    dlg.ValueField.Enable = 'on';
                    dlg.ValueField.Placeholder = mps.tr( ...
                        '例如 1、-0.5、pi/4', 'e.g. 1, -0.5, pi/4');
                    dlg.HintLabel.Text = dlg.lockHint( ...
                        mps.tr('新值 = 当前新值 + 偏移量。', ...
                        'New value = current new value + offset.'), locked);
                case 'reset'
                    dlg.ValueLabel.Text = '—';
                    dlg.ValueField.Enable = 'off';
                    dlg.HintLabel.Text = mps.tr( ...
                        '把所有目标参数的新值恢复为脚本里的原值。', ...
                        'Reset the new value of every target to the value in the script.');
                case 'useon'
                    dlg.ValueLabel.Text = '—';
                    dlg.ValueField.Enable = 'off';
                    dlg.HintLabel.Text = mps.tr( ...
                        '勾选目标参数，让它们参与本次运行。', ...
                        'Select the target parameters so they are used in this run.');
                case 'useoff'
                    dlg.ValueLabel.Text = '—';
                    dlg.ValueField.Enable = 'off';
                    dlg.HintLabel.Text = mps.tr( ...
                        '取消勾选目标参数，本次运行保持原值。', ...
                        'Clear the target parameters so this run keeps their original values.');
                case 'lock'
                    dlg.ValueLabel.Text = '—';
                    dlg.ValueField.Enable = 'off';
                    dlg.HintLabel.Text = mps.tr( ...
                        '锁定目标参数：新值永远等于脚本原值。', ...
                        'Lock the targets: the new value always equals the script value.');
                case 'unlock'
                    dlg.ValueLabel.Text = '—';
                    dlg.ValueField.Enable = 'off';
                    dlg.HintLabel.Text = mps.tr( ...
                        '解锁目标参数，允许修改新值。', ...
                        'Unlock the targets so their new value can be edited.');
                case 'paste'
                    dlg.ValueLabel.Text = mps.tr('剪贴板', 'Clipboard');
                    dlg.ValueField.Enable = 'off';
                    dlg.HintLabel.Text = mps.tr( ...
                        ['从剪贴板读取每行一个数值表达式，按表格顺序填入 %d 行。' ...
                         '需要先在 Excel 里复制一列。'], ...
                        ['Read one numeric expression per line from the clipboard ' ...
                         'and fill %d rows in table order. ' ...
                         'Copy a column in Excel first.'], n);
                otherwise
                    dlg.ValueLabel.Text = '—';
                    dlg.ValueField.Enable = 'off';
                    dlg.HintLabel.Text = '';
            end
        end

        % -----------------------------------------------------------------
        function labels = opLabels(dlg) %#ok<INUSD>
            labels = {mps.tr('设为固定值', 'Set to value'), ...
                mps.tr('乘以系数', 'Multiply by'), ...
                mps.tr('加上偏移', 'Add offset'), ...
                mps.tr('恢复原值', 'Reset to original'), ...
                mps.tr('勾选', 'Use'), ...
                mps.tr('取消勾选', 'Do not use'), ...
                mps.tr('锁定', 'Lock'), ...
                mps.tr('解锁', 'Unlock'), ...
                mps.tr('从剪贴板填入新值', 'Paste new values from clipboard')};
        end

        % -----------------------------------------------------------------
        function txt = lockHint(dlg, txt, locked) %#ok<INUSD>
            if locked > 0
                txt = mps.tr('%s 已锁定的参数会自动跳过。', ...
                    '%s Locked parameters are skipped automatically.', txt);
            end
        end

        % -----------------------------------------------------------------
        function key = operationKey(dlg)
            idx = find(strcmp(dlg.OpDrop.Items, dlg.OpDrop.Value), 1);
            if isempty(idx)
                key = 'set';
            else
                key = dlg.OpKeys{idx};
            end
        end

        % -----------------------------------------------------------------
        function indices = targetIndices(dlg)
            idx = find(strcmp(dlg.ScopeDrop.Items, dlg.ScopeDrop.Value), 1);
            if isempty(idx)
                idx = 1;
            end
            switch dlg.ScopeKeys{idx}
                case 'selected'
                    indices = dlg.SelectedIdx;
                case 'visible'
                    indices = dlg.VisibleIdx;
                otherwise
                    indices = 1:numel(dlg.Params);
            end
            indices = double(indices(:)');
            indices = unique(indices(indices >= 1 & ...
                indices <= numel(dlg.Params)));
        end

        % -----------------------------------------------------------------
        function onApply(dlg)
            indices = dlg.targetIndices();
            if isempty(indices)
                uialert(dlg.UIFigure, ...
                    mps.tr('没有可修改的参数。', 'No parameters to edit.'), ...
                    mps.tr('没有目标', 'No targets'), 'Icon', 'warning');
                return;
            end

            op = dlg.operationKey();
            value = strtrim(char(dlg.ValueField.Value));
            values = {};

            switch op
                case 'set'
                    [ok, ~] = mps.validateValue(value);
                    if ~ok || isempty(value)
                        uialert(dlg.UIFigure, mps.tr( ...
                            '“%s”不是有效的数值表达式。', ...
                            '"%s" is not a valid numeric expression.', value), ...
                            mps.tr('输入无效', 'Invalid input'), ...
                            'Icon', 'warning');
                        return;
                    end
                case {'scale', 'offset'}
                    [ok, operand] = mps.validateValue(value);
                    if ~ok || ~isnumeric(operand) || ~isscalar(operand) || ...
                            ~isreal(operand) || ~isfinite(operand)
                        uialert(dlg.UIFigure, ...
                            mps.tr(['系数/偏移量必须是有限实数，' ...
                            '例如 2、0.5、pi/2。'], ...
                            ['The factor/offset must be a finite real number, ' ...
                             'e.g. 2, 0.5, pi/2.']), ...
                            mps.tr('输入无效', 'Invalid input'), ...
                            'Icon', 'warning');
                        return;
                    end
                case 'paste'
                    [values, err] = dlg.readClipboard(indices);
                    if ~isempty(err)
                        uialert(dlg.UIFigure, err, ...
                            mps.tr('剪贴板不可用', 'Clipboard unavailable'), ...
                            'Icon', 'warning');
                        return;
                    end
            end

            dlg.Result = struct('indices', indices, 'op', op, ...
                'value', value, 'values', {values});
            if ~isempty(dlg.UIFigure) && isvalid(dlg.UIFigure)
                delete(dlg.UIFigure);
            end
        end

        % -----------------------------------------------------------------
        function [values, err] = readClipboard(dlg, indices)
            values = {};
            err = '';
            try
                text = clipboard('paste');
            catch
                err = mps.tr('无法读取系统剪贴板。', ...
                    'Cannot read the system clipboard.');
                return;
            end
            if isempty(text)
                err = mps.tr('剪贴板是空的。请先在 Excel 里复制一列数值。', ...
                    'The clipboard is empty. Copy a column of numbers in Excel first.');
                return;
            end
            lines = regexp(char(text), '\r\n|\r|\n', 'split');
            lines = cellfun(@strtrim, lines, 'UniformOutput', false);
            values = lines(~cellfun(@isempty, lines));
            if numel(values) ~= numel(indices)
                err = mps.tr( ...
                    ['剪贴板有 %d 个值，但目标有 %d 行。' ...
                     '请让两者数量一致后再试。'], ...
                    ['The clipboard has %d values but there are %d target rows. ' ...
                     'Make the counts match and try again.'], ...
                    numel(values), numel(indices));
                values = {};
                return;
            end
            for k = 1:numel(values)
                [ok, ~] = mps.validateValue(values{k});
                if ~ok
                    err = mps.tr('剪贴板第 %d 行的值无效：%s', ...
                        'Line %d of the clipboard is invalid: %s', ...
                        k, values{k});
                    values = {};
                    return;
                end
            end
        end
    end
end
