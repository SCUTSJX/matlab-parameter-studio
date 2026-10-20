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
            [file, path] = uigetfile( ...
                {'*.m', mps.tr('MATLAB 脚本 (*.m)', ...
                'MATLAB script (*.m)')}, ...
                mps.tr('选择 MATLAB 脚本', 'Select a MATLAB script'), ...
                startDir);
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
                uialert(app.UIFigure, ...
                    mps.tr('请先在参数表里选中一行。', ...
                    'Select a row in the parameter table first.'), ...
                    mps.tr('没有选中参数', 'No parameter selected'), ...
                    'Icon', 'warning');
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
                obj.StatusFcn(mps.tr( ...
                    '已在 MATLAB 编辑器中打开：%s 第 %d 行。', ...
                    'Opened in the MATLAB editor: %s, line %d.', ...
                    file, lineNo));
            catch
                try
                    edit(file);
                    obj.StatusFcn(mps.tr( ...
                        '已打开源文件（未能定位到第 %d 行）。', ...
                        'Opened the source file (could not jump to line %d).', ...
                        lineNo));
                catch err
                    uialert(app.UIFigure, err.message, ...
                        mps.tr('打开失败', 'Open failed'), ...
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
                obj.StatusFcn(mps.tr( ...
                    '源文件已被外部修改，无法%s；请先重新扫描。', ...
                    ['The source file changed externally; cannot %s. ' ...
                     'Rescan first.'], actionLabel));
                ok = false;
                return;
            end
            rescanOption = mps.tr('重新扫描并保留修改', ...
                'Rescan and keep edits');
            continueOption = mps.tr('仍然继续', 'Continue anyway');
            cancelOption = mps.tr('取消', 'Cancel');
            choice = uiconfirm(app.UIFigure, mps.tr( ...
                ['源文件在扫描后被外部修改了。\n\n' ...
                 '继续%s可能把值写到旧的行号位置。建议先重新扫描并保留修改。'], ...
                ['The source file changed after the scan.\n\n' ...
                 'Continuing to %s may write values to stale line ' ...
                 'numbers. Rescanning and keeping edits is recommended.'], ...
                actionLabel), mps.tr('源文件已变化', 'Source changed'), ...
                'Options', {rescanOption, continueOption, cancelOption}, ...
                'DefaultOption', 1, 'CancelOption', 3);
            switch choice
                case rescanOption
                    obj.rescanKeepingEdits();
                case continueOption
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
            obj.StatusFcn(mps.tr( ...
                '已重新扫描并保留修改：匹配 %d，重名跳过 %d，未匹配 %d。', ...
                ['Rescanned and kept edits: %d matched, ' ...
                 '%d ambiguous, %d unmatched.'], ...
                stats.matched, stats.ambiguous, stats.unmatched));
        end

        function rescanDiscardingEdits(obj)
            app = obj.App;
            if isempty(app.SourceFile)
                return;
            end
            if any([app.Params.isChanged])
                continueOption = mps.tr('继续', 'Continue');
                cancelOption = mps.tr('取消', 'Cancel');
                choice = uiconfirm(app.UIFigure, mps.tr( ...
                    '重新扫描会丢弃当前修改的新值。是否继续？', ...
                    ['Rescanning will discard the new values you have ' ...
                     'edited. Continue?']), mps.tr('重新扫描', 'Rescan'), ...
                    'Options', {continueOption, cancelOption}, ...
                    'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(choice, continueOption)
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
