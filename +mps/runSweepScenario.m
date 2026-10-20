function out = runSweepScenario(sourceFile, baseParams, activeIdx, values, ...
    runDir, keepFigures, xName, yNames, maxVariableMB, maxTotalMB, ...
    saveFigFiles, figureResolution)
%RUNSWEEPSCENARIO Execute one sweep scenario on a parallel worker.
%
%   Returns a slim, serializable result: figure paths, workspace summary and
%   only the selected X/Y vectors (large workspaces stay on the worker).

    if nargin < 11, saveFigFiles = false; end
    if nargin < 12, figureResolution = 150; end
    out = struct('ok', false, 'error', '', ...
        'figures', struct('path', {}, 'title', {}, 'figFile', {}), ...
        'elapsed', 0, 'workspaceData', struct(), ...
        'workspace', struct('name', {}, 'class', {}, 'size', {}, ...
        'min', {}, 'max', {}, 'preview', {}));
    tempScript = '';
    keepScript = fullfile(runDir, 'run_script.m');
    try
        if ~isfolder(runDir)
            mkdir(runDir);
        end
        params = baseParams;
        for j = 1:numel(activeIdx)
            params(activeIdx(j)).newValue = ...
                num2str(values{j}, '%.10g');
            params(activeIdx(j)).use = true;
        end

        sourceDir = fileparts(sourceFile);
        tempScript = fullfile(sourceDir, sprintf( ...
            'mps_sweep_%s_%d.m', datestr(now, 'HHMMSSFFF'), randi(1e9)));
        try
            mps.applyEdits(sourceFile, params, tempScript, ...
                'NeutralizeCloseAll', true);
        catch
            tempScript = keepScript;
            mps.applyEdits(sourceFile, params, tempScript, ...
                'NeutralizeCloseAll', true);
        end
        r = mps.runScript(sourceFile, tempScript, runDir, ...
            'MaxVariableMB', maxVariableMB, 'MaxTotalMB', maxTotalMB, ...
            'SaveFigFiles', saveFigFiles, ...
            'FigureResolution', figureResolution);
        try
            if ~strcmpi(tempScript, keepScript) && ...
                    ~isfile(keepScript)
                copyfile(tempScript, keepScript);
            end
        catch
        end

        out.ok = r.ok;
        out.error = r.error;
        out.figures = r.figures;
        out.elapsed = r.elapsedSeconds;
        out.workspace = r.workspace;
        out.workspaceData = slimWorkspace(r.workspaceData, xName, yNames);

        if ~keepFigures
            for k = 1:numel(r.figureHandles)
                if isvalid(r.figureHandles(k))
                    close(r.figureHandles(k));
                end
            end
        else
            % Workers should not keep figures alive between scenarios.
            for k = 1:numel(r.figureHandles)
                if isvalid(r.figureHandles(k))
                    close(r.figureHandles(k));
                end
            end
        end
    catch err
        out.ok = false;
        out.error = getReport(err, 'extended', 'hyperlinks', 'off');
    end
    if ~isempty(tempScript) && ~strcmpi(tempScript, keepScript) && ...
            isfile(tempScript)
        try
            delete(tempScript);
        catch
        end
    end
end

% -------------------------------------------------------------------------
function slim = slimWorkspace(ws, xName, yNames)
    slim = struct();
    if ~isstruct(ws)
        return;
    end
    names = {};
    if ~isempty(xName) && ~strcmp(xName, '(无)')
        names{end+1} = xName;
    end
    if ischar(yNames) || isstring(yNames)
        yNames = cellstr(yNames);
    end
    for k = 1:numel(yNames)
        if ~strcmp(yNames{k}, '(无)')
            names{end+1} = yNames{k}; %#ok<AGROW>
        end
    end
    for k = 1:numel(names)
        if isfield(ws, names{k})
            v = ws.(names{k});
            if (isnumeric(v) || islogical(v)) && isvector(v)
                slim.(names{k}) = v;
            end
        end
    end
end
