function out = runProjectSweepScenario(projectRoot, entryFile, baseParams, ...
    activeIdx, values, runDir, xName, yNames, maxVariableMB, maxTotalMB, ...
    lazyWorkspaceMB, saveFigFiles, figureResolution, seed)
%RUNPROJECTSWEEPSCENARIO Execute one project sweep scenario on a worker.
%
%   seed is optional.  When provided, the worker sets the random stream to
%   that seed immediately before running the project entry script.

    if nargin < 11, lazyWorkspaceMB = 32; end
    if nargin < 12, saveFigFiles = false; end
    if nargin < 13, figureResolution = 150; end
    out = struct('ok', false, 'error', '', ...
        'figures', struct('path', {}, 'title', {}, 'figFile', {}), ...
        'elapsed', 0, 'workspaceData', struct(), ...
        'workspace', struct('name', {}, 'class', {}, 'size', {}, ...
        'min', {}, 'max', {}, 'preview', {}));
    try
        params = baseParams;
        for j = 1:numel(activeIdx)
            params(activeIdx(j)).newValue = ...
                num2str(values{j}, '%.10g');
            params(activeIdx(j)).use = true;
        end
        ex = mps.ProjectRunExecutor(entryFile, entryFile, params, false);
        ex.OutDir = runDir;
        ex.MaxVariableMB = maxVariableMB;
        ex.MaxTotalMB = maxTotalMB;
        ex.LazyWorkspaceMB = lazyWorkspaceMB;
        ex.SaveFigFiles = saveFigFiles;
        ex.FigureResolution = figureResolution;
        ex.CopyProjectResults = false;
        ex.UseShadowCache = true;
        ex.ResetShadowResults = true;
        ex.SlimWorkspace = true;
        ex.SlimNames = [{xName}, yNames];
        ex.Progress = @(message) [];
        if nargin >= 14 && ~isempty(seed)
            rng(double(seed), 'twister');
        end
        result = ex.run();
        r = result.run;
        out.ok = r.ok;
        out.error = r.error;
        out.figures = r.figures;
        out.elapsed = r.elapsedSeconds;
        out.workspace = r.workspace;
        out.workspaceData = r.workspaceData;
    catch err
        out.ok = false;
        out.error = getReport(err, 'extended', 'hyperlinks', 'off');
    end
end
