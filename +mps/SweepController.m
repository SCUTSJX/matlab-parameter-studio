classdef SweepController < handle
    %SWEEPController Run the batch sweep dialog and report workflow.
    %
    %   App keeps the public command runSweepWithValues as a thin alias.
    %   UI handles and callbacks that are private to App are supplied in Ctx.

    properties
        Ctx
        SweepStartedAt = 0
    end

    methods
        function obj = SweepController(ctx)
            obj.Ctx = ctx;
        end

        function summary = runWithValues(obj, names, valueLists, xName, yNames)
            app = obj.Ctx.App;
            if ischar(names) || isstring(names)
                names = cellstr(names);
            end
            if isnumeric(valueLists)
                valueLists = {valueLists};
            end
            activeIdx = [];
            for k = 1:numel(names)
                idx = find(strcmp({app.Params.name}, names{k}), 1);
                if isempty(idx)
                    error('mps:App:paramNotFound', ...
                        mps.tr('找不到参数：%s', ...
                            'Parameter not found: %s', names{k}));
                end
                activeIdx(end+1) = idx; %#ok<AGROW>
            end
            if nargin < 4 || isempty(xName)
                xName = '';
            end
            if nargin < 5 || isempty(yNames)
                yNames = {};
            end
            overlay = ~isempty(xName) && ~isempty(yNames);
            summary = obj.run(activeIdx, valueLists, overlay, ...
                xName, yNames);
        end

        function onOpen(obj)
            app = obj.Ctx.App;
            if isempty(app.SourceFile)
                uialert(app.UIFigure, ...
                    mps.tr('请先打开一个 .m 文件。', ...
                    'Open a .m file first.'), ...
                    mps.tr('没有文件', 'No file'), 'Icon', 'warning');
                return;
            end
            if app.IsFunctionFile
                uialert(app.UIFigure, ...
                    mps.tr('这是函数文件，不能直接扫描运行。请打开调用它的脚本。', ...
                    ['This is a function file and cannot be run as a ' ...
                     'sweep. Open the script that calls it.']), ...
                    mps.tr('无法批量扫描', 'Cannot run a batch sweep'), ...
                    'Icon', 'warning');
                return;
            end
            if app.Busy
                return;
            end
            dlg = mps.SweepDialog(app.Params, app.Results.LastWorkspace);
            uiwait(dlg.UIFigure);
            result = dlg.Result;
            delete(dlg);
            if ~isstruct(result) || ~isfield(result, 'activeIdx') || ...
                    isempty(result.activeIdx)
                return;   % cancelled
            end
            obj.run(result.activeIdx, result.values, ...
                result.overlay, result.xName, result.yNames, ...
                result.parallel, result.maxScenarios);
        end

        function summary = run(obj, activeIdx, values, overlay, ...
                xName, yNames, parallel, maxScenarios)
            %RUN Execute the cartesian product and build reports.
            app = obj.Ctx.App;
            ctx = obj.Ctx;
            if nargin < 7
                parallel = false;
            end
            if nargin < 8 || isempty(maxScenarios)
                maxScenarios = 24;
            end
            summary = struct('ok', false, 'sweepRoot', '', 'count', 0, ...
                'report', '', 'overlayPath', '', 'metricsPath', '', ...
                'canceled', false);
            if isempty(app.SourceFile) || isempty(activeIdx)
                return;
            end
            if ~ctx.ConfirmFcn(mps.tr('批量扫描', 'Batch sweep'))
                return;
            end

            ctx.SetBusyFcn(true);
            obj.SweepStartedAt = tic;
            if strcmp(app.UIFigure.Visible, 'on')
                d = uiprogressdlg(app.UIFigure, ...
                    'Title', mps.tr('批量扫描', 'Batch sweep'), ...
                    'Message', mps.tr('准备...', 'Preparing...'), ...
                    'Indeterminate', 'off', ...
                    'Value', 0, 'Cancelable', 'on', ...
                    'CancelText', mps.tr('取消剩余组', ...
                    'Cancel remaining runs'));
            else
                d = [];
            end
            oldHV = app.UIFigure.HandleVisibility;
            app.UIFigure.HandleVisibility = 'off';
            cleanupObj = onCleanup(@() obj.finish(d, oldHV)); %#ok<NASGU>
            hadPool = ~isempty(gcp('nocreate'));

            try
                runner = mps.SweepRunner(app.SourceFile, app.Params, ...
                    activeIdx, values, overlay, xName, yNames, ...
                    ctx.KeepFiguresCheck.Value);
                runner.MaxVariableMB = app.MaxVariableMB;
                runner.MaxTotalMB = app.MaxTotalMB;
                runner.LazyWorkspaceMB = app.LazyWorkspaceMB;
                runner.SaveFigFiles = app.SaveFigFiles;
                runner.FigureResolution = app.FigureResolution;
                runner.NumWorkers = app.NumWorkers;
                runner.MaxWorkers = app.MaxWorkers;
                runner.BaseSeed = app.SweepSeed;
                runner.MaxScenarios = maxScenarios;
                runner.ProjectMode = app.ProjectMode;
                runner.EntryFile = app.EntryFile;
                runner.Parallel = logical(parallel);
                runner.Progress = @(fraction, message) ...
                    obj.updateProgress(d, fraction, message);
                runner.ShouldCancel = @() obj.cancelRequested(d);
                out = runner.run();

                app.Results.LastRun = out.agg;
                app.Results.LastWorkspace = out.agg.workspaceData;
                app.Results.OutputDir = out.sweepRoot;
                app.Results.LastReport = out.report;
                app.Results.refreshAll();
                if isempty(out.agg.log)
                    ctx.LogArea.Value = {''};
                else
                    ctx.LogArea.Value = splitlines(out.agg.log);
                end
                ctx.ReportButton.Enable = 'on';
                ctx.FolderButton.Enable = 'on';
                ctx.CloseFiguresButton.Enable = 'on';
                ctx.CompareButton.Enable = 'on';

                summary.ok = true;
                summary.sweepRoot = out.sweepRoot;
                summary.count = out.count;
                summary.report = out.report;
                summary.overlayPath = out.overlayPath;
                summary.metricsPath = out.metricsPath;
                summary.canceled = out.canceled;
                if out.canceled
                    ctx.StatusLabel.Text = mps.tr( ...
                        '批量扫描已取消：已完成 %d 组，报告：%s', ...
                        ['Batch sweep canceled: %d scenarios completed, ' ...
                         'report: %s'], out.count, out.report);
                elseif isempty(out.metricsPath)
                    ctx.StatusLabel.Text = mps.tr( ...
                        '批量扫描完成：%d 组，%d 张图。报告：%s', ...
                        ['Batch sweep complete: %d scenarios, ' ...
                         '%d figures. Report: %s'], ...
                        out.count, numel(out.agg.figures), out.report);
                else
                    ctx.StatusLabel.Text = mps.tr( ...
                        '批量扫描完成：%d 组，%d 张图。指标 CSV：%s', ...
                        ['Batch sweep complete: %d scenarios, ' ...
                         '%d figures. Metrics CSV: %s'], ...
                        out.count, numel(out.agg.figures), out.metricsPath);
                end
            catch err
                ctx.StatusLabel.Text = [mps.tr('批量扫描失败：', ...
                    'Batch sweep failed: ') err.message];
                uialert(app.UIFigure, err.message, ...
                    mps.tr('批量扫描失败', 'Batch sweep failed'), ...
                    'Icon', 'error');
            end
            if ~hadPool && ~app.KeepParallelPool
                try
                    delete(gcp('nocreate'));
                catch err
                    mps.logWarning(mps.tr('关闭扫描并行池', ...
                        'Close the sweep parallel pool'), err, 'Silent', true);
                end
            end
            clear cleanupObj;
        end

        function updateProgress(obj, d, fraction, message) %#ok<INUSD>
            if ~isempty(d) && isvalid(d)
                d.Value = min(max(fraction, 0), 1);
                if fraction > 0.01 && fraction < 1 && ...
                        obj.SweepStartedAt > 0
                    elapsed = toc(obj.SweepStartedAt);
                    remaining = elapsed * (1 - fraction) / fraction;
                    d.Message = mps.tr( ...
                        '%s（已用 %.0f s，预计剩余 %.0f s）', ...
                        ['%s (elapsed %.0f s, about %.0f s remaining)'], ...
                        message, elapsed, remaining);
                else
                    d.Message = message;
                end
            end
            drawnow;
        end

        function tf = cancelRequested(~, d)
            tf = false;
            if ~isempty(d) && isvalid(d)
                try
                    tf = logical(d.CancelRequested);
                catch
                    % 对话框可能已关闭或失效；读取失败时按未请求取消处理
                end
            end
        end

        function finish(obj, d, oldHV)
            if ~isempty(d) && isvalid(d)
                delete(d);
            end
            app = obj.Ctx.App;
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                app.UIFigure.HandleVisibility = oldHV;
            end
            obj.Ctx.SetBusyFcn(false);
        end
    end
end
