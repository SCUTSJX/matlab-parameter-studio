classdef SourceController < handle
%SOURCECONTROLLER Source-change detection and rescan workflows.
%
%   App keeps status/table refresh callbacks here so the pure source logic
%   does not have to know about private App widgets.

    properties
        App
        TableCtl
        RefreshFcn = @() []
        StatusFcn = @(message) []
    end

    methods
        function obj = SourceController(app, tableCtl)
            obj.App = app;
            obj.TableCtl = tableCtl;
        end

        function changed = sourceChanged(obj)
            changed = false;
            app = obj.App;
            if app.ProjectMode && ~isempty(app.ProjectRoot)
                try
                    changed = ~strcmp( ...
                        mps.projectStamp(app.ProjectRoot).signature, ...
                        app.ProjectStamp);
                catch
                    changed = true;
                end
                return;
            end
            if isempty(app.SourceFile) || ...
                    isempty(fieldnames(app.SourceStamp))
                return;
            end
            try
                current = mps.sourceStamp(app.SourceFile);
                changed = ~mps.sameSourceStamp(app.SourceStamp, current);
            catch
                changed = true;
            end
        end

        function ok = ensureSourceCurrent(obj, actionLabel)
            ok = true;
            if ~obj.sourceChanged()
                return;
            end
            app = obj.App;
            if ~strcmp(app.UIFigure.Visible, 'on')
                obj.StatusFcn(sprintf( ...
                    '源文件已被外部修改，无法%s；请先重新扫描。', actionLabel));
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
                    obj.rescanKeepingEdits();
                case '仍然继续'
                    % The user explicitly accepts the stale positions.
                otherwise
                    ok = false;
            end
        end

        function rescanKeepingEdits(obj)
            app = obj.App;
            if isempty(app.SourceFile)
                return;
            end
            oldParams = app.Params;
            oldAnnotations = app.LastAnnotations;
            oldAnnotationFile = app.AnnotationFile;
            obj.deleteSession();
            obj.reloadSource();
            preset = struct('name', '重扫前修改', ...
                'values', mps.paramsToValues(oldParams));
            [app.Params, stats] = mps.applyPreset(app.Params, preset);
            if ~isempty(oldAnnotations)
                [app.Params, ~] = mps.applyAnnotations( ...
                    app.Params, oldAnnotations);
                app.LastAnnotations = oldAnnotations;
                app.AnnotationFile = oldAnnotationFile;
            end
            obj.TableCtl.markDirty();
            obj.RefreshFcn();
            obj.StatusFcn(sprintf( ...
                '已重新扫描并保留修改：匹配 %d，重名跳过 %d，未匹配 %d。', ...
                stats.matched, stats.ambiguous, stats.unmatched));
        end

        function rescanDiscardingEdits(obj)
            app = obj.App;
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
            obj.deleteSession();
            obj.reloadSource();
        end
    end

    methods (Access = private)
        function deleteSession(obj)
            try
                delete(mps.sessionPath(obj.App.SourceFile));
            catch err
                mps.logWarning('删除旧会话', err);
            end
        end

        function reloadSource(obj)
            if obj.App.ProjectMode
                obj.App.loadProject(obj.App.SourceFile);
            else
                obj.App.loadFile(obj.App.SourceFile, 'RestoreSession', false);
            end
        end
    end
end
