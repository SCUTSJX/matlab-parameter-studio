classdef DiffDialog < handle
%DIFFDIALOG Show the exact text that will be saved before writing it.
%
%   dlg = mps.DiffDialog(title, diffLines);
%   uiwait(dlg.UIFigure);
%   if dlg.Result
%       % user confirmed
%   end
%   delete(dlg);

    properties
        UIFigure
        Result = false
    end

    methods
        function dlg = DiffDialog(title, diffLines, varargin)
            visible = 'on';
            for k = 1:2:numel(varargin)
                if k + 1 > numel(varargin), break; end
                if strcmpi(char(varargin{k}), 'Visible')
                    visible = char(varargin{k+1});
                end
            end
            dlg.createUI(title, diffLines);
            if strcmpi(visible, 'off')
                dlg.UIFigure.Visible = 'off';
            end
            dlg.UIFigure.UserData = dlg;
        end

        function delete(dlg)
            if ~isempty(dlg.UIFigure) && isvalid(dlg.UIFigure)
                delete(dlg.UIFigure);
            end
        end

        function confirm(dlg)
            dlg.Result = true;
            if ~isempty(dlg.UIFigure) && isvalid(dlg.UIFigure)
                delete(dlg.UIFigure);
            end
        end

        function cancel(dlg)
            dlg.Result = false;
            if ~isempty(dlg.UIFigure) && isvalid(dlg.UIFigure)
                delete(dlg.UIFigure);
            end
        end
    end

    methods (Access = private)
        function createUI(dlg, title, diffLines)
            dlg.UIFigure = uifigure('Name', '保存前确认', ...
                'Position', [260 140 900 620]);
            try
                dlg.UIFigure.Theme = 'light';   % R2025a+
            catch
            end
            dlg.UIFigure.CloseRequestFcn = @(s, e) dlg.cancel();

            root = uigridlayout(dlg.UIFigure, [3 1]);
            root.RowHeight = {42, '1x', 36};
            root.Padding = [14 14 14 14];
            root.RowSpacing = 8;

            if isempty(title)
                title = '即将写入的改动';
            end
            header = uilabel(root, 'Text', title, ...
                'FontWeight', 'bold', 'Interpreter', 'none');
            header.Layout.Row = 1;

            if ischar(diffLines) || isstring(diffLines)
                diffLines = cellstr(diffLines);
            end
            area = uitextarea(root, 'Editable', 'off', ...
                'FontName', 'Consolas', 'FontSize', 11, ...
                'Value', diffLines);
            area.Layout.Row = 2;

            buttons = uigridlayout(root, [1 3]);
            buttons.Layout.Row = 3;
            buttons.ColumnWidth = {'1x', 90, 120};
            buttons.Padding = [0 0 0 0];
            uibutton(buttons, 'Text', '取消', ...
                'ButtonPushedFcn', @(s, e) dlg.cancel());
            confirmButton = uibutton(buttons, 'Text', '确认保存', ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.18 0.45 0.85], ...
                'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(s, e) dlg.confirm());
            confirmButton.Layout.Column = 3;
        end
    end
end
