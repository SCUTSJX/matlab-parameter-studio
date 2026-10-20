function out = backgroundProjectRun(sourceFile, entryFile, params, ...
    maxVariableMB, maxTotalMB, saveFigFiles, figureResolution, ...
    lazyWorkspaceMB)
%BACKGROUNDPROJECTRUN Worker-side entry for a project-mode background run.

    if nargin < 6, saveFigFiles = false; end
    if nargin < 7, figureResolution = 150; end
    if nargin < 8, lazyWorkspaceMB = 32; end
    executor = mps.ProjectRunExecutor(sourceFile, entryFile, params, false);
    executor.MaxVariableMB = maxVariableMB;
    executor.MaxTotalMB = maxTotalMB;
    executor.LazyWorkspaceMB = lazyWorkspaceMB;
    executor.SaveFigFiles = saveFigFiles;
    executor.FigureResolution = figureResolution;
    executor.Progress = @(message) [];
    out = executor.run();
    if isfield(out, 'run') && isfield(out.run, 'figureHandles')
        out.run.figureHandles = gobjects(0);
    end
end
