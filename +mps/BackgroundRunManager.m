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
                    'Title', '后台运行', 'Message', '准备...', ...
                    'Indeterminate', 'on', 'Cancelable', 'on', ...
                    'CancelText', '取消运行');
            end
            if ~isempty(obj.ParentFigure) && isvalid(obj.ParentFigure)
                obj.OldHV = obj.ParentFigure.HandleVisibility;
                obj.ParentFigure.HandleVisibility = 'off';
            end
            obj.Canceled = false;
            obj.TimedOut = false;
            obj.StartedAt = tic;
            try
                obj.setProgress('启动并行池...');
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
                catch err
                    mps.logWarning('为并行 worker 添加应用路径', err, ...
                        'Silent', true);
                end
                obj.setProgress('后台运行 MATLAB 脚本...');
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
                    mps.logWarning('取消后台运行', err);
                end
            end
            if ~isempty(d) && isvalid(d) && ~obj.Canceled
                if obj.TimeoutSeconds > 0
                    d.Message = sprintf( ...
                        '后台运行中... 已用 %.0f s（上限 %d s）', ...
                        toc(obj.StartedAt), obj.TimeoutSeconds);
                else
                    d.Message = sprintf('后台运行中... 已用 %.0f s', ...
                        toc(obj.StartedAt));
                end
            end

            state = obj.Future.State;
            if ~any(strcmp(state, {'finished', 'cancelled'}))
                return;
            end
            if obj.Canceled
                if obj.TimedOut
                    msg = sprintf('后台运行超时（%d s），已取消。', ...
                        obj.TimeoutSeconds);
                else
                    msg = '后台运行已取消。';
                end
                obj.finish([], msg);
                return;
            end
            try
                out = fetchOutputs(obj.Future);
            catch err
                obj.finish([], err.message);
                return;
            end
            obj.finish(out, '');
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
                    mps.logWarning('取消后台运行', err);
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
                mps.logWarning('处理后台运行结果', err);
            end
        end

        function cleanup(obj)
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                try
                    stop(obj.Timer);
                    delete(obj.Timer);
                catch err
                    mps.logWarning('清理后台运行计时器', err, ...
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
                    mps.logWarning('关闭后台并行池', err, 'Silent', true);
                end
            end
            obj.CreatedPool = false;
        end
    end
end
