classdef RunHistoryController < handle
    %RUNHISTORYCONTROLLER Browse past runs and load their parameters.
    %
    %   App keeps the RunHistoryDialog wiring and the parameter-loading
    %   confirmation flow here instead of in App.m.

    properties
        App
        StatusLabel
        UndoFcn = @() []
        RefreshFcn = @() []
    end

    methods
        function obj = RunHistoryController(app, statusLabel)
            obj.App = app;
            obj.StatusLabel = statusLabel;
        end

        function onOpen(obj)
            app = obj.App;
            if isempty(app.SourceFile)
                uialert(app.UIFigure, '请先打开一个 .m 文件。', ...
                    '没有文件', 'Icon', 'warning');
                return;
            end
            root = fullfile(fileparts(app.SourceFile), ...
                'parameter_studio_runs');
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
            obj.apply(result);
        end

        function apply(obj, result)
            app = obj.App;
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
            obj.UndoFcn();
            try
                [params, stats] = mps.applyPreset(app.Params, preset);
                app.Params = params;
            catch err
                uialert(app.UIFigure, err.message, '载入失败', ...
                    'Icon', 'error');
                return;
            end
            obj.RefreshFcn();
            obj.StatusLabel.Text = sprintf( ...
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
    end
end
