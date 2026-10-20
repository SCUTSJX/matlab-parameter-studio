function out = backgroundProjectRun(sourceFile, entryFile, params, ...
    maxVariableMB, maxTotalMB)
%BACKGROUNDPROJECTRUN Worker-side entry for a project-mode background run.

    executor = mps.ProjectRunExecutor(sourceFile, entryFile, params, false);
    executor.MaxVariableMB = maxVariableMB;
    executor.MaxTotalMB = maxTotalMB;
    executor.Progress = @(message) [];
    out = executor.run();
    if isfield(out, 'run') && isfield(out.run, 'figureHandles')
        out.run.figureHandles = gobjects(0);
    end
end
