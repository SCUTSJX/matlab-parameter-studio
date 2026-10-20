classdef AnnotationController < handle
    %ANNOTATIONCONTROLLER Generate, import and clear parameter annotations.
    %
    %   App keeps the public commands exportAnnotationTemplate /
    %   importAnnotations / clearAnnotations as thin aliases.

    properties
        App
        StatusLabel
        UndoFcn = @() []
        RefreshFcn = @() []
    end

    methods
        function obj = AnnotationController(app, statusLabel)
            obj.App = app;
            obj.StatusLabel = statusLabel;
        end

        function path = exportTemplate(obj, jsonPath)
            mps.writeAnnotationTemplate(obj.App.SourceFile, ...
                obj.App.Params, jsonPath);
            path = jsonPath;
        end

        function stats = importFile(obj, jsonPath)
            anns = mps.readAnnotations(jsonPath);
            obj.UndoFcn();
            [params, stats] = mps.applyAnnotations(obj.App.Params, anns);
            obj.App.Params = params;
            obj.App.LastAnnotations = anns;
            obj.App.AnnotationFile = jsonPath;
            obj.RefreshFcn();
        end

        function clear(obj)
            obj.onClear();
        end

        function onWrite(obj)
            if isempty(obj.App.SourceFile)
                uialert(obj.App.UIFigure, '请先打开一个 .m 文件。', ...
                    '没有文件', 'Icon', 'warning');
                return;
            end
            [~, base] = fileparts(obj.App.SourceFile);
            defaultName = fullfile(fileparts(obj.App.SourceFile), ...
                [base '_annotations.json']);
            [file, path] = uiputfile({'*.json', 'JSON 文件 (*.json)'}, ...
                '生成注释模板 JSON', defaultName);
            if isequal(file, 0)
                return;
            end
            target = fullfile(path, file);
            try
                mps.writeAnnotationTemplate(obj.App.SourceFile, ...
                    obj.App.Params, target);
            catch err
                uialert(obj.App.UIFigure, err.message, '生成失败', ...
                    'Icon', 'error');
                return;
            end
            obj.StatusLabel.Text = sprintf('注释模板已生成：%s', target);
            uialert(obj.App.UIFigure, sprintf( ...
                ['注释模板已生成：\n%s\n\n' ...
                 '使用方法：把该 JSON 发给 AI（或自己填写），让 AI 为每个参数的 ' ...
                 'description（含义）和 unit（单位）赋值，然后回到本应用点“导入注释”。\n\n' ...
                 '重新打开同一个 .m 文件时，如果旁边存在 <文件名>_annotations.json，' ...
                 '会自动载入。'], target), '生成成功', 'Icon', 'info');
        end

        function onImport(obj)
            if isempty(obj.App.SourceFile)
                uialert(obj.App.UIFigure, '请先打开一个 .m 文件。', ...
                    '没有文件', 'Icon', 'warning');
                return;
            end
            [file, path] = uigetfile({'*.json', 'JSON 文件 (*.json)'}, ...
                '导入注释 JSON', fileparts(obj.App.SourceFile));
            if isequal(file, 0)
                return;
            end
            target = fullfile(path, file);
            try
                anns = mps.readAnnotations(target);
            catch err
                uialert(obj.App.UIFigure, err.message, '导入失败', ...
                    'Icon', 'error');
                return;
            end
            obj.UndoFcn();
            [params, stats] = mps.applyAnnotations(obj.App.Params, anns);
            obj.App.Params = params;
            obj.App.LastAnnotations = anns;
            obj.App.AnnotationFile = target;
            obj.RefreshFcn();
            msg = sprintf(['已读取 %d 条注释：\n' ...
                '  匹配到参数：%d\n  重名无法匹配：%d\n  未匹配：%d\n  空注释跳过：%d'], ...
                numel(anns), stats.matched, stats.ambiguous, ...
                stats.unmatched, stats.skipped);
            obj.StatusLabel.Text = sprintf( ...
                '已导入注释：匹配 %d / %d 条（%s）', ...
                stats.matched, numel(anns), target);
            if stats.matched == 0 && stats.skipped < numel(anns)
                uialert(obj.App.UIFigure, [msg, sprintf( ...
                    '\n\n提示：注释里的变量名需要和“参数”列一致；id 匹配最准确。')], ...
                    '没有匹配到参数', 'Icon', 'warning');
            else
                uialert(obj.App.UIFigure, msg, '导入注释', 'Icon', 'info');
            end
        end

        function onClear(obj)
            obj.UndoFcn();
            for k = 1:numel(obj.App.Params)
                obj.App.Params(k).description = '';
                obj.App.Params(k).unit = '';
            end
            obj.App.LastAnnotations = struct([]);
            obj.App.AnnotationFile = '';
            obj.RefreshFcn();
            obj.StatusLabel.Text = '已清空当前参数上的注释。';
        end
    end
end
