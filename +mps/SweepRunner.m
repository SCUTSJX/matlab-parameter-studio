classdef SweepRunner < handle
%SWEEPRUNNER Execute a parameter sweep and build its reports.
%
%   runner = mps.SweepRunner(sourceFile, params, activeIdx, values, ...
%                            overlay, xName, yNames, keepFigures);
%   runner.Progress = @(fraction, message) ...;
%   out = runner.run();
%
%   out fields: ok, sweepRoot, count, report, overlayPath, metricsPath,
%   agg (the aggregate run shown in the app), results, metrics.
%
%   The runner owns scenario execution, figure visibility, overlay drawing
%   and report writing.  App keeps the progress dialog and UI updates.

    properties
        SourceFile = ''
        EntryFile = ''
        ProjectMode = false
        Params = struct([])
        ActiveIdx = []
        Values = {}
        Overlay = false
        XName = ''
        YNames = {}
        KeepFigures = false
        MaxVariableMB = 100
        MaxTotalMB = 512
        LazyWorkspaceMB = 32
        SaveFigFiles = false
        FigureResolution = 150
        MaxScenarios = 24
        NumWorkers = 0
        Parallel = false
        Progress = @(fraction, message) []
        ShouldCancel = @() false
    end

    methods
        function obj = SweepRunner(sourceFile, params, activeIdx, values, ...
                overlay, xName, yNames, keepFigures)
            obj.SourceFile = char(sourceFile);
            obj.Params = params;
            obj.ActiveIdx = activeIdx(:)';
            obj.Values = values;
            obj.Overlay = logical(overlay);
            obj.XName = char(xName);
            if ischar(yNames) || isstring(yNames)
                obj.YNames = cellstr(yNames);
            else
                obj.YNames = yNames;
            end
            if nargin >= 8
                obj.KeepFigures = logical(keepFigures);
            end
        end

        function out = run(obj)
            names = {obj.Params(obj.ActiveIdx).name};
            scenarios = mps.sweepScenarios(names, obj.Values, ...
                obj.MaxScenarios);
            sweepRoot = obj.makeSweepRoot();
            results = struct('label', {}, 'runDir', {}, 'ok', {}, ...
                'error', {}, 'figures', {}, 'elapsed', {}, ...
                'workspace', {}, 'workspaceData', {});

            total = numel(scenarios);
            canceled = false;
            if obj.Parallel && license('test', 'Distrib_Computing_Toolbox')
                try
                    [results, canceled] = obj.runParallel(sweepRoot, scenarios);
                catch err
                    obj.Progress(0, sprintf( ...
                        '并行启动失败，改为串行：%s', err.message));
                    [results, canceled] = obj.runSerial(sweepRoot, scenarios);
                end
            else
                [results, canceled] = obj.runSerial(sweepRoot, scenarios);
            end
            if ~isempty(results)
                keep = arrayfun(@(r) ~isempty(r.label), results);
                results = results(keep);
            end

            if canceled
                obj.Progress(0.97, '已取消剩余组，正在生成已完成部分的报告...');
            else
                obj.Progress(0.97, '生成叠加曲线和报告...');
            end
            overlayPath = '';
            if obj.Overlay
                overlayPath = obj.makeOverlay(sweepRoot, results);
            end
            metrics = mps.sweepMetrics(results, obj.XName, obj.YNames);
            agg = obj.aggregate(sweepRoot, results, overlayPath);
            agg.metrics = metrics;
            [reportPath, metricsPath] = mps.writeSweepReport( ...
                sweepRoot, obj.SourceFile, names, obj.Values, scenarios, ...
                results, overlayPath, metrics);
            obj.Progress(1, '完成。');

            out = struct();
            out.ok = true;
            out.canceled = canceled;
            out.sweepRoot = sweepRoot;
            out.count = numel(results);
            out.report = reportPath;
            out.overlayPath = overlayPath;
            out.metricsPath = metricsPath;
            out.agg = agg;
            out.results = results;
            out.metrics = metrics;
        end
    end

    methods (Access = private)
        function slim = loadSelected(obj, matFile)
            names = {};
            if ~isempty(obj.XName) && ~strcmp(obj.XName, '(无)')
                names{end+1} = obj.XName;
            end
            for k = 1:numel(obj.YNames)
                if ~strcmp(obj.YNames{k}, '(无)')
                    names{end+1} = obj.YNames{k}; %#ok<AGROW>
                end
            end
            slim = struct();
            if isempty(names), return; end
            try
                S = load(matFile, names{:});
                for k = 1:numel(names)
                    if isfield(S, names{k}) && ...
                            (isnumeric(S.(names{k})) || islogical(S.(names{k}))) && ...
                            isvector(S.(names{k}))
                        slim.(names{k}) = S.(names{k});
                    end
                end
            catch
            end
        end

        function results = emptyResults(~)
            results = struct('label', {}, 'runDir', {}, 'ok', {}, ...
                'error', {}, 'figures', {}, 'elapsed', {}, ...
                'workspace', {}, 'workspaceData', {});
        end

        function [results, canceled] = runSerial(obj, sweepRoot, scenarios)
            results = obj.emptyResults();
            canceled = false;
            total = numel(scenarios);
            oldVis = get(groot, 'defaultFigureVisible');
            set(groot, 'defaultFigureVisible', 'off');
            figCleaner = onCleanup(@() set(groot, ...
                'defaultFigureVisible', oldVis)); %#ok<NASGU>

            for k = 1:total
                if obj.ShouldCancel()
                    canceled = true;
                    break;
                end
                obj.Progress((k - 1) / max(total, 1), ...
                    sprintf('运行 %d/%d：%s', k, total, scenarios(k).label));
                runDir = fullfile(sweepRoot, sprintf('run_%02d', k));
                if ~isfolder(runDir)
                    mkdir(runDir);
                end
                params = obj.Params;
                for j = 1:numel(obj.ActiveIdx)
                    params(obj.ActiveIdx(j)).newValue = ...
                        num2str(scenarios(k).values{j}, '%.10g');
                    params(obj.ActiveIdx(j)).use = true;
                end

                if obj.ProjectMode
                    ex = mps.ProjectRunExecutor(obj.EntryFile, ...
                        obj.EntryFile, params, false);
                    ex.OutDir = runDir;
                    ex.MaxVariableMB = obj.MaxVariableMB;
                    ex.MaxTotalMB = obj.MaxTotalMB;
                    ex.LazyWorkspaceMB = obj.LazyWorkspaceMB;
                    ex.SaveFigFiles = obj.SaveFigFiles;
                    ex.FigureResolution = obj.FigureResolution;
                    ex.CopyProjectResults = false;
                    ex.UseShadowCache = true;
                    ex.ResetShadowResults = true;
                    ex.SlimWorkspace = true;
                    if obj.Overlay
                        ex.SlimNames = [{obj.XName}, obj.YNames];
                    end
                    ex.Progress = @(message) obj.Progress( ...
                        (k - 1) / max(total, 1), message);
                    out = ex.run();
                    r = out.run;
                else
                    [tempScript, keepScript] = obj.makeTempScript(runDir);
                    cleaner = onCleanup(@() obj.removeTempScript( ...
                        tempScript, keepScript)); %#ok<NASGU>
                    mps.applyEdits(obj.SourceFile, params, tempScript, ...
                        'NeutralizeCloseAll', true);
                    r = mps.runScript(obj.SourceFile, tempScript, runDir, ...
                        'MaxVariableMB', obj.MaxVariableMB, ...
                        'MaxTotalMB', obj.MaxTotalMB, ...
                        'LazyWorkspaceMB', obj.LazyWorkspaceMB, ...
                        'SaveFigFiles', obj.SaveFigFiles, ...
                        'FigureResolution', obj.FigureResolution);
                    try
                        if ~isfile(keepScript) && ...
                                ~strcmpi(tempScript, keepScript)
                            copyfile(tempScript, keepScript);
                        end
                        if isfile(keepScript)
                            r.scriptPath = keepScript;
                        end
                    catch
                    end
                    clear cleaner;
                end
                obj.handleFigures(r);
                if obj.Overlay && isempty(r.workspaceData) && ...
                        ~isempty(r.matFile) && isfile(r.matFile)
                    r.workspaceData = obj.loadSelected(r.matFile);
                end

                results(end+1) = struct( ...
                    'label', scenarios(k).label, ...
                    'runDir', runDir, 'ok', r.ok, ...
                    'error', r.error, 'figures', {r.figures}, ...
                    'elapsed', r.elapsedSeconds, ...
                    'workspace', {r.workspace}, ...
                    'workspaceData', {r.workspaceData}); %#ok<AGROW>
            end
        end

        function [results, canceled] = runParallel(obj, sweepRoot, scenarios)
            results = obj.emptyResults();
            canceled = false;
            total = numel(scenarios);
            if total == 0
                return;
            end

            obj.Progress(0, '启动并行池...');
            pool = gcp('nocreate');
            if isempty(pool)
                if obj.NumWorkers > 0
                    pool = parpool('Processes', obj.NumWorkers);
                else
                    pool = parpool('Processes');
                end
            end
            root = fileparts(fileparts(which('mps.SweepRunner')));
            try
                wait(parfevalOnAll(pool, @addpath, 0, root));
            catch
            end

            futures = cell(1, total);
            for k = 1:total
                runDir = fullfile(sweepRoot, sprintf('run_%02d', k));
                if ~isfolder(runDir)
                    mkdir(runDir);
                end
                if obj.ProjectMode
                    futures{k} = parfeval(pool, ...
                        @mps.runProjectSweepScenario, 1, ...
                        fileparts(obj.EntryFile), obj.EntryFile, ...
                        obj.Params, obj.ActiveIdx, scenarios(k).values, ...
                        runDir, obj.XName, obj.YNames, ...
                        obj.MaxVariableMB, obj.MaxTotalMB, ...
                        obj.LazyWorkspaceMB, obj.SaveFigFiles, ...
                        obj.FigureResolution);
                else
                    futures{k} = parfeval(pool, @mps.runSweepScenario, 1, ...
                        obj.SourceFile, obj.Params, obj.ActiveIdx, ...
                        scenarios(k).values, runDir, false, obj.XName, ...
                        obj.YNames, obj.MaxVariableMB, obj.MaxTotalMB, ...
                        obj.SaveFigFiles, obj.FigureResolution, ...
                        obj.LazyWorkspaceMB);
                end
            end
            futureArray = [futures{:}];

            for done = 1:total
                if obj.ShouldCancel()
                    try
                        cancel(futureArray);
                    catch
                    end
                    canceled = true;
                    break;
                end
                [idx, res] = fetchNext(futureArray);
                results(idx) = struct( ...
                    'label', scenarios(idx).label, ...
                    'runDir', fullfile(sweepRoot, sprintf('run_%02d', idx)), ...
                    'ok', res.ok, 'error', res.error, ...
                    'figures', {res.figures}, 'elapsed', res.elapsed, ...
                    'workspace', {res.workspace}, ...
                    'workspaceData', {res.workspaceData}); %#ok<AGROW>
                obj.Progress(done / total, ...
                    sprintf('完成 %d/%d：%s', done, total, ...
                    scenarios(idx).label));
            end
        end

        function sweepRoot = makeSweepRoot(obj)
            base = fileparts(obj.SourceFile);
            root = fullfile(base, 'parameter_studio_runs');
            if ~isfolder(root)
                mkdir(root);
            end
            stamp = datestr(now, 'yyyymmdd_HHMMSS');
            sweepRoot = fullfile(root, [stamp '_sweep']);
            n = 2;
            while isfolder(sweepRoot)
                sweepRoot = fullfile(root, ...
                    sprintf('%s_sweep_%d', stamp, n));
                n = n + 1;
            end
            mkdir(sweepRoot);
        end

        function [tempScript, keepScript] = makeTempScript(obj, runDir)
            keepScript = fullfile(runDir, 'run_script.m');
            runDirSrc = fileparts(obj.SourceFile);
            tempScript = fullfile(runDirSrc, ...
                sprintf('mps_sweep_%s.m', datestr(now, 'HHMMSSFFF')));
            if isfile(tempScript)
                tempScript = fullfile(runDirSrc, ...
                    sprintf('mps_sweep_%s_%d.m', ...
                    datestr(now, 'HHMMSSFFF'), randi(9999)));
            end
            try
                fid = fopen(tempScript, 'w');
                if fid >= 0
                    fclose(fid);
                    delete(tempScript);
                else
                    tempScript = keepScript;
                end
            catch
                tempScript = keepScript;
            end
        end

        function removeTempScript(~, tempScript, keepScript)
            if ~strcmpi(tempScript, keepScript) && isfile(tempScript)
                try
                    delete(tempScript);
                catch
                end
            end
        end

        function handleFigures(obj, r)
            if obj.KeepFigures
                for k = 1:numel(r.figureHandles)
                    if isvalid(r.figureHandles(k))
                        set(r.figureHandles(k), 'Visible', 'on');
                    end
                end
            else
                for k = 1:numel(r.figureHandles)
                    if isvalid(r.figureHandles(k))
                        delete(r.figureHandles(k));
                    end
                end
                r.figureHandles = gobjects(0);
            end
        end

        function agg = aggregate(obj, sweepRoot, results, overlayPath)
            agg = struct();
            agg.ok = true;
            agg.error = '';
            agg.figures = struct('path', {}, 'title', {}, 'figFile', {});
            agg.workspace = struct('name', {}, 'class', {}, 'size', {}, ...
                'min', {}, 'max', {}, 'preview', {});
            agg.workspaceData = struct();
            agg.log = '';
            agg.outDir = sweepRoot;
            agg.scriptPath = '';
            agg.sourceFile = obj.SourceFile;
            agg.matFile = '';
            agg.figureHandles = gobjects(0);
            agg.elapsedSeconds = 0;

            if ~isempty(overlayPath)
                agg.figures(end+1) = struct('path', overlayPath, ...
                    'title', '叠加曲线', 'figFile', '');
            end
            for k = 1:numel(results)
                agg.elapsedSeconds = agg.elapsedSeconds + results(k).elapsed;
                for j = 1:numel(results(k).figures)
                    f = results(k).figures(j);
                    agg.figures(end+1) = struct('path', f.path, ...
                        'title', sprintf('%02d · %s · %s', k, ...
                        results(k).label, f.title), 'figFile', f.figFile); %#ok<AGROW>
                end
                if ~isempty(results(k).error)
                    agg.log = [agg.log, sprintf('--- run %02d (%s) ---\n%s\n', ...
                        k, results(k).label, results(k).error)];
                end
            end
            if ~isempty(results)
                agg.workspaceData = results(end).workspaceData;
                if isfield(results(end), 'workspace') && ...
                        ~isempty(results(end).workspace)
                    agg.workspace = results(end).workspace;
                else
                    agg.workspace = mps.summarizeWorkspace(agg.workspaceData);
                end
            end
        end

        function overlayPath = makeOverlay(obj, sweepRoot, results)
            overlayPath = '';
            if isempty(obj.XName) || strcmp(obj.XName, '(无)') || ...
                    isempty(obj.YNames)
                return;
            end
            yNames = obj.YNames;
            if ischar(yNames) || isstring(yNames)
                yNames = cellstr(yNames);
            end
            fig = figure('Visible', 'off', 'Color', 'w');
            half = onCleanup(@() delete(fig)); %#ok<NASGU>
            hold on;
            grid on;
            plotted = 0;
            cmap = lines(max(7, numel(results)));
            styles = {'-', '--', ':', '-.'};
            for k = 1:numel(results)
                ws = results(k).workspaceData;
                if ~isstruct(ws) || ~isfield(ws, obj.XName)
                    continue;
                end
                x = ws.(obj.XName);
                if ~(isnumeric(x) || islogical(x)) || ~isvector(x)
                    continue;
                end
                for j = 1:numel(yNames)
                    if ~isfield(ws, yNames{j})
                        continue;
                    end
                    y = ws.(yNames{j});
                    if ~(isnumeric(y) || islogical(y)) || ~isvector(y) || ...
                            numel(x) ~= numel(y)
                        continue;
                    end
                    if numel(yNames) == 1
                        label = results(k).label;
                    else
                        label = sprintf('%s | %s', ...
                            results(k).label, yNames{j});
                    end
                    style = styles{mod(j - 1, numel(styles)) + 1};
                    plot(x, y, style, 'LineWidth', 1.2, ...
                        'Color', cmap(k, :), 'DisplayName', label);
                    plotted = plotted + 1;
                end
            end
            if plotted == 0
                return;
            end
            xlabel(obj.XName, 'Interpreter', 'none');
            ylabel('值');
            title('批量扫描叠加曲线');
            legend('Location', 'eastoutside', 'Interpreter', 'none', ...
                'FontSize', 9);
            overlayPath = fullfile(sweepRoot, 'overlay.png');
            try
                exportgraphics(fig, overlayPath, 'Resolution', 150, ...
                    'BackgroundColor', 'white');
            catch
                overlayPath = '';
            end
            clear half;
        end
    end
end
