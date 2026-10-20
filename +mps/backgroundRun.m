function out = backgroundRun(sourceFile, params, maxVariableMB, maxTotalMB, ...
    saveFigFiles, figureResolution)
%BACKGROUNDRUN Worker-side entry for a single background simulation.
%
%   Called by App through parfeval.  Figure handles are not serializable, so
%   they are stripped from the returned result; the PNG/FIG files and report
%   are already on disk.

    if nargin < 5, saveFigFiles = false; end
    if nargin < 6, figureResolution = 150; end
    executor = mps.RunExecutor(sourceFile, params, false);
    executor.MaxVariableMB = maxVariableMB;
    executor.MaxTotalMB = maxTotalMB;
    executor.SaveFigFiles = saveFigFiles;
    executor.FigureResolution = figureResolution;
    executor.Progress = @(message) [];
    out = executor.run();
    if isfield(out, 'run') && isfield(out.run, 'figureHandles')
        out.run.figureHandles = gobjects(0);
    end
end
