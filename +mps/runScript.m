function result = runScript(sourceFile, scriptPath, outDir)
%RUNSCRIPT Execute a generated script and capture figures, workspace and log.
%
%   result = mps.runScript(sourceFile, scriptPath, outDir)
%
%   sourceFile is the original script (for metadata), scriptPath is the
%   generated copy to execute, and outDir is the result folder.
%
%   The app protects its own uifigure with HandleVisibility='off', so a
%   script that calls "close all" does not close the studio.  In addition,
%   mps.applyEdits normally replaces "close all" with a harmless statement
%   in the generated copy.

    t0 = tic;
    result = struct();
    result.ok = false;
    result.error = '';
    result.figures = struct('path', {}, 'title', {}, 'figFile', {});
    result.workspace = struct('name', {}, 'class', {}, 'size', {}, ...
        'min', {}, 'max', {}, 'preview', {});
    result.workspaceData = struct();
    result.figureHandles = gobjects(0);
    result.log = '';
    result.outDir = outDir;
    result.scriptPath = scriptPath;
    result.matFile = '';
    result.sourceFile = sourceFile;

    if ~isfolder(outDir)
        mkdir(outDir);
    end
    figDir = fullfile(outDir, 'figures');
    if ~isfolder(figDir)
        mkdir(figDir);
    end

    oldFigs = findall(groot, 'Type', 'figure');
    oldPwd = pwd;
    logFile = fullfile(outDir, 'console.log');

    diary off;
    diary(logFile);
    diary on;
    cleanupObj = onCleanup(@() cleanupRun()); %#ok<NASGU>

    try
        ws = mps.executeScript(scriptPath);
        result.workspaceData = ws.data;
        result.workspace = mps.summarizeWorkspace(ws.data);
        result.ok = ws.ok;
        result.error = ws.error;
    catch err
        result.ok = false;
        result.error = getReport(err, 'extended', 'hyperlinks', 'off');
    end

    diary off;
    try
        cd(oldPwd);
    catch
    end

    % Capture figures that appeared during this run.
    allFigs = findall(groot, 'Type', 'figure');
    newFigs = gobjects(0);
    for k = 1:numel(allFigs)
        f = allFigs(k);
        if isempty(oldFigs) || ~any(f == oldFigs)
            newFigs(end+1) = f; %#ok<AGROW>
        end
    end
    if ~isempty(newFigs)
        try
            [~, order] = sort([newFigs.Number]);
            newFigs = newFigs(order);
        catch
        end
    end
    result.figureHandles = newFigs;

    for k = 1:numel(newFigs)
        f = newFigs(k);
        if ~isvalid(f)
            continue;
        end
        pngPath = fullfile(figDir, sprintf('fig_%02d.png', k));
        wrote = false;
        try
            exportgraphics(f, pngPath, 'Resolution', 150, ...
                'BackgroundColor', 'white');
            wrote = true;
        catch
            try
                saveas(f, pngPath);
                wrote = true;
            catch
            end
        end
        figFile = '';
        try
            figFile = fullfile(figDir, sprintf('fig_%02d.fig', k));
            savefig(f, figFile);
        catch
            figFile = '';
        end
        if wrote
            title = '';
            try
                title = get(f, 'Name');
            catch
            end
            if isempty(title)
                title = sprintf('图 %d', k);
            end
            result.figures(end+1) = struct('path', pngPath, ...
                'title', title, 'figFile', figFile);
        end
    end

    % Save workspace variables for later inspection / plotting.
    if isstruct(result.workspaceData) && ~isempty(fieldnames(result.workspaceData))
        try
            wsData = result.workspaceData; %#ok<NASGU>
            matFile = fullfile(outDir, 'workspace.mat');
            save(matFile, '-struct', 'wsData');
            result.matFile = matFile;
        catch
            try
                wsData = result.workspaceData; %#ok<NASGU>
                matFile = fullfile(outDir, 'workspace.mat');
                save(matFile, '-struct', 'wsData', '-v7.3');
                result.matFile = matFile;
            catch
            end
        end
    end

    if isfile(logFile)
        try
            result.log = fileread(logFile);
        catch
        end
    end

    % Make error messages point at the user's own file instead of the
    % generated temp script (mps_run_*.m), otherwise the line references
    % are confusing.
    if ~isempty(result.error)
        result.error = mapScriptPath(result.error, scriptPath, sourceFile);
    end
    if ~isempty(result.log)
        result.log = mapScriptPath(result.log, scriptPath, sourceFile);
    end

    result.elapsedSeconds = toc(t0);

    clear cleanupObj;

    function cleanupRun()
        diary off;
        try
            cd(oldPwd);
        catch
        end
    end
end

% -------------------------------------------------------------------------
function txt = mapScriptPath(txt, scriptPath, sourceFile)
%MAPSCRIPTPATH Replace the generated script name with the original file.
    if isempty(txt) || isempty(scriptPath) || isempty(sourceFile)
        return;
    end
    [~, tmpBase, tmpExt] = fileparts(scriptPath);
    [~, srcBase, srcExt] = fileparts(sourceFile);
    txt = strrep(txt, scriptPath, sourceFile);
    txt = strrep(txt, [tmpBase tmpExt], [srcBase srcExt]);
    % MATLAB stack traces often print the function name without extension.
    txt = strrep(txt, tmpBase, srcBase);
end
