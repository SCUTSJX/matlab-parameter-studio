classdef BackgroundRunManager < handle
%BACKGROUNDRUNMANAGER Own the lifecycle of one PCT background run.
%
%   The manager handles the parallel pool, progress dialog, timer, timeout,
%   cancellation and cleanup.  App supplies a launch callback and a finish
%   callback so UI state stays in App.

    properties
        ParentFigure
        RootPath = ''
        BackgroundWorkers = 1
        KeepParallelPool = false
        TimeoutSeconds = 0
        ProgressFcn = @(message) []
        FinishedFcn = @(out, errorMessage) []
    end

    properties (Access = private)
        Future
        Timer
        Dialog
        OldHV
        Canceled = false
        TimedOut = false
        StartedAt = 0
        CreatedPool = false
    end

    methods
        function obj = BackgroundRunManager(parentFigure)
            if nargin >= 1
                obj.ParentFigure = parentFigure;
            end
        end

        function start(obj, launchFcn)
            if ~isempty(obj.Future)
                return;
            end
            obj.Dialog = [];
            if ~isempty(obj.ParentFigure) && isvalid(obj.ParentFigure) && ...
                    strcmp(obj.ParentFigure.Visible, 'on')
                obj.Dialog = uiprogressdlg(obj.ParentFigure, ...
                    'Title', mps.tr('后台运行', 'Background run'), ...
                    'Message', mps.tr('准备...', 'Preparing...'), ...
                    'Indeterminate', 'on', 'Cancelable', 'on', ...
                    'CancelText', mps.tr('取消运行', 'Cancel run'));
            end
            if ~isempty(obj.ParentFigure) && isvalid(obj.ParentFigure)
                obj.OldHV = obj.ParentFigure.HandleVisibility;
                obj.ParentFigure.HandleVisibility = 'off';
            end
            obj.Canceled = false;
            obj.TimedOut = false;
            obj.StartedAt = tic;
            try
                obj.setProgress(mps.tr('启动并行池...', ...
                    'Starting parallel pool...'));
                pool = gcp('nocreate');
                obj.CreatedPool = isempty(pool);
                if isempty(pool)
                    pool = parpool('Processes', ...
                        max(1, obj.BackgroundWorkers));
                end
                root = obj.RootPath;
                if isempty(root)
                    root = fileparts(fileparts(which('mps.App')));
                end
                try
                    wait(parfevalOnAll(pool, @addpath, 0, root));
                    wait(parfevalOnAll(pool, @mps.setLanguage, 0, ...
                        mps.language()));
                catch err
                    mps.logWarning(mps.tr('为并行 worker 添加应用路径', ...
                        'Add the app path to parallel workers'), err, ...
                        'Silent', true);
                end
                obj.setProgress(mps.tr('后台运行 MATLAB 脚本...', ...
                    'Running MATLAB script in the background...'));
                obj.Future = launchFcn(pool);
                obj.Timer = timer( ...
                    'ExecutionMode', 'fixedSpacing', 'Period', 0.5, ...
                    'TimerFcn', @(~, ~) obj.poll());
                start(obj.Timer);
            catch err
                obj.finish([], err.message);
            end
        end

        function poll(obj)
            if isempty(obj.Future)
                return;
            end
            d = obj.Dialog;
            if ~isempty(d) && isvalid(d)
                try
                    if d.CancelRequested
                        obj.Canceled = true;
                        cancel(obj.Future);
                    end
                catch
                    % 对话框可能已关闭；此处取消失败不影响后续轮询
                end
            end
            if obj.TimeoutSeconds > 0 && ...
                    toc(obj.StartedAt) > obj.TimeoutSeconds
                obj.TimedOut = true;
                obj.Canceled = true;
                try
                    cancel(obj.Future);
                catch err
                    mps.logWarning(mps.tr('取消后台运行', ...
                        'Cancel background run'), err);
                end
            end
            if ~isempty(d) && isvalid(d) && ~obj.Canceled
                if obj.TimeoutSeconds > 0
                    d.Message = mps.tr( ...
                        '后台运行中... 已用 %.0f s（上限 %d s）', ...
                        ['Background run in progress... %.0f s used ' ...
                         '(limit %d s)'], ...
                        toc(obj.StartedAt), obj.TimeoutSeconds);
                else
                    d.Message = mps.tr( ...
                        '后台运行中... 已用 %.0f s', ...
                        'Background run in progress... %.0f s used', ...
                        toc(obj.StartedAt));
                end
            end

            state = obj.Future.State;
            if ~any(strcmp(state, {'finished', 'cancelled'}))
                return;
            end
            if strcmp(state, 'finished')
                % The run completed, possibly in the same poll cycle that a
                % cancel request or timeout was registered.  Deliver the
                % results instead of throwing them away.
                try
                    out = fetchOutputs(obj.Future);
                catch err
                    obj.finish([], err.message);
                    return;
                end
                obj.finish(out, '');
                return;
            end
            if obj.TimedOut
                msg = mps.tr('后台运行超时（%d s），已取消。', ...
                    'Background run timed out after %d s and was canceled.', ...
                    obj.TimeoutSeconds);
            else
                msg = mps.tr('后台运行已取消。', ...
                    'Background run canceled.');
            end
            obj.finish([], msg);
        end

        function setProgress(obj, message)
            if ~isempty(obj.Dialog) && isvalid(obj.Dialog)
                obj.Dialog.Message = message;
            end
            drawnow;
        end

        function cancel(obj)
            if ~isempty(obj.Future)
                try
                    cancel(obj.Future);
                catch err
                    mps.logWarning(mps.tr('取消后台运行', ...
                        'Cancel background run'), err);
                end
            end
            obj.cleanup();
        end
    end

    methods (Access = private)
        function finish(obj, out, errorMessage)
            obj.cleanup();
            try
                obj.FinishedFcn(out, errorMessage);
            catch err
                mps.logWarning(mps.tr('处理后台运行结果', ...
                    'Handle the background run result'), err);
            end
        end

        function cleanup(obj)
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                try
                    stop(obj.Timer);
                    delete(obj.Timer);
                catch err
                    mps.logWarning(mps.tr('清理后台运行计时器', ...
                        'Clean up the background run timer'), err, ...
                        'Silent', true);
                end
            end
            obj.Timer = [];
            if ~isempty(obj.Dialog) && isvalid(obj.Dialog)
                delete(obj.Dialog);
            end
            obj.Dialog = [];
            if ~isempty(obj.ParentFigure) && isvalid(obj.ParentFigure) && ...
                    ~isempty(obj.OldHV)
                obj.ParentFigure.HandleVisibility = obj.OldHV;
            end
            obj.OldHV = [];
            obj.Future = [];
            obj.Canceled = false;
            obj.TimedOut = false;
            if obj.CreatedPool && ~obj.KeepParallelPool
                try
                    delete(gcp('nocreate'));
                catch err
                    mps.logWarning(mps.tr('关闭后台并行池', ...
                        'Close the background parallel pool'), err, ...
                        'Silent', true);
                end
            end
            obj.CreatedPool = false;
        end
    end
end
