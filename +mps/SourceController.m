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
        RunFcn = @() []
        BulkFcn = @() []
        UndoFcn = @() []
        RedoFcn = @() []
    end

    methods
        function obj = SourceController(app, tableCtl)
            obj.App = app;
            obj.TableCtl = tableCtl;
        end

        function handleKeyPress(obj, event)
            %HANDLEKEYPRESS F5 / Ctrl+Enter = run, Ctrl+O = open.
            if ~isstruct(event) || ~isfield(event, 'Key')
                return;
            end
            key = lower(event.Key);
            mods = {};
            if isfield(event, 'Modifier')
                if iscell(event.Modifier)
                    mods = event.Modifier;
                elseif ischar(event.Modifier)
                    mods = {event.Modifier};
                end
            end
            hasCtrl = any(strcmpi(mods, 'control'));
            hasShift = any(strcmpi(mods, 'shift'));
            if strcmp(key, 'f5') || (strcmp(key, 'return') && hasCtrl)
                obj.RunFcn();
            elseif strcmp(key, 'o') && hasCtrl
                obj.openFileDialog();
            elseif strcmp(key, 'b') && hasCtrl
                obj.BulkFcn();
            elseif strcmp(key, 'z') && hasCtrl
                if hasShift
                    obj.RedoFcn();
                else
                    obj.UndoFcn();
                end
            elseif strcmp(key, 'y') && hasCtrl
                obj.RedoFcn();
            end
        end

        function openFileDialog(obj)
            app = obj.App;
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

        function openInEditor(obj, varargin)
            %OPENINEDITOR Jump to the selected parameter's source line.
            app = obj.App;
            if ~isempty(varargin) && isstruct(varargin{1}) && ...
                    isfield(varargin{1}, 'Indices') && ...
                    ~isempty(varargin{1}.Indices)
                % Only the read-only 参数/行 columns open the editor; a
                % double-click on 新值 must keep working as cell editing.
                indices = varargin{1}.Indices;
                if size(indices, 2) < 2
                    return;
                end
                col = indices(1, 2);
                if ~ismember(col, [4 7])
                    return;
                end
            end
            if isempty(app.SourceFile) || isempty(app.SelectedParams)
                uialert(app.UIFigure, '请先在参数表里选中一行。', ...
                    '没有选中参数', 'Icon', 'warning');
                return;
            end
            idx = app.SelectedParams(end);
            lineNo = app.Params(idx).line;
            file = app.Params(idx).sourceFile;
            if isempty(file)
                file = app.SourceFile;
            end
            try
                matlab.desktop.editor.openAndGoToLine( ...
                    file, max(1, lineNo));
                obj.StatusFcn(sprintf( ...
                    '已在 MATLAB 编辑器中打开：%s 第 %d 行。', file, lineNo));
            catch
                try
                    edit(file);
                    obj.StatusFcn(sprintf( ...
                        '已打开源文件（未能定位到第 %d 行）。', lineNo));
                catch err
                    uialert(app.UIFigure, err.message, '打开失败', ...
                        'Icon', 'error');
                end
            end
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
