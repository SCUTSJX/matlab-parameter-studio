classdef ManualParamController < handle
    %MANUALPARAMCONTROLLER Add or edit a user-defined parameter.
    %
    %   The controller persists the parameter in <source>_manual.json and
    %   keeps App's undo/table refresh callbacks.

    properties
        App
        StatusLabel
        UndoFcn = @() []
        RefreshFcn = @() []
    end

    methods
        function obj = ManualParamController(app, statusLabel)
            obj.App = app;
            obj.StatusLabel = statusLabel;
        end

        function onAdd(obj)
            app = obj.App;
            if isempty(app.SourceFile)
                uialert(app.UIFigure, '请先打开一个 .m 文件。', ...
                    '没有文件', 'Icon', 'warning');
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
            obj.UndoFcn();
            if editIdx > 0
                p.use = app.Params(editIdx).use;
                p.locked = app.Params(editIdx).locked;
                app.Params(editIdx) = p;
                action = '已更新';
            else
                app.Params(end+1) = p;
                action = '已添加';
            end
            obj.RefreshFcn();
            mps.writeManualParams(app.SourceFile, app.Params);
            obj.StatusLabel.Text = sprintf( ...
                '%s手动参数：%s = %s（下次打开会自动恢复）', ...
                action, p.name, p.newValue);
        end
    end
end
