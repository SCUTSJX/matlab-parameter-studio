function metrics = sweepMetrics(results, xName, yNames)
%SWEEPMETRICS Compute simple, objective-agnostic metrics for sweep runs.
%
%   metrics = mps.sweepMetrics(results, xName, yNames)
%
%   results is the struct array built by App.runSweep.  Each entry must
%   contain label, ok, elapsed, figures and workspaceData.  xName / yNames
%   are the same variables used for the overlay curve.  When they are empty,
%   one run-level row per scenario is still returned so the caller can write
%   a useful CSV.
%
%   Metric fields (NaN when the variables are unavailable):
%       run, label, ok, elapsed, figures, yName,
%       minValue, maxValue, finalValue, absPeak, rms, peakTime

    metrics = emptyMetrics();
    if isempty(results)
        return;
    end

    xName = strtrim(char(xName));
    if strcmp(xName, '(无)')
        xName = '';
    end
    if ischar(yNames) || isstring(yNames)
        yNames = cellstr(yNames);
    end
    yNames = yNames(~cellfun(@isempty, yNames));
    yNames = yNames(~strcmp(yNames, '(无)'));

    for k = 1:numel(results)
        r = results(k);
        base = struct( ...
            'run', k, ...
            'label', charField(r, 'label'), ...
            'ok', logicalField(r, 'ok', true), ...
            'elapsed', numberField(r, 'elapsed', NaN), ...
            'figures', numel(fieldOrDefault(r, 'figures', struct([]))), ...
            'yName', '', 'minValue', NaN, 'maxValue', NaN, ...
            'finalValue', NaN, 'absPeak', NaN, 'rms', NaN, ...
            'peakTime', NaN);

        ws = fieldOrDefault(r, 'workspaceData', struct());
        if isempty(xName) || ~isstruct(ws) || ~isfield(ws, xName)
            metrics(end+1) = base; %#ok<AGROW>
            continue;
        end
        x = ws.(xName);
        if ~(isnumeric(x) || islogical(x)) || ~isvector(x) || isempty(x) || ...
                ~isreal(x)
            metrics(end+1) = base; %#ok<AGROW>
            continue;
        end

        if isempty(yNames)
            metrics(end+1) = base; %#ok<AGROW>
            continue;
        end

        for j = 1:numel(yNames)
            row = base;
            yName = char(yNames{j});
            row.yName = yName;
            if isfield(ws, yName)
                y = ws.(yName);
                if (isnumeric(y) || islogical(y)) && isvector(y) && ...
                        numel(y) == numel(x) && ~isempty(y) && isreal(y)
                    xv = double(x(:));
                    yv = double(y(:));
                    row.minValue = min(yv);
                    row.maxValue = max(yv);
                    row.finalValue = yv(end);
                    absY = abs(yv);
                    [row.absPeak, peakIdx] = max(absY);
                    row.peakTime = xv(peakIdx);
                    row.rms = sqrt(mean(yv.^2));
                end
            end
            metrics(end+1) = row; %#ok<AGROW>
        end
    end
end

% -------------------------------------------------------------------------
function metrics = emptyMetrics()
    metrics = struct('run', {}, 'label', {}, 'ok', {}, 'elapsed', {}, ...
        'figures', {}, 'yName', {}, 'minValue', {}, 'maxValue', {}, ...
        'finalValue', {}, 'absPeak', {}, 'rms', {}, 'peakTime', {});
end

% -------------------------------------------------------------------------
function value = fieldOrDefault(s, name, defaultValue)
    value = defaultValue;
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        value = s.(name);
    end
end

% -------------------------------------------------------------------------
function s = charField(item, name)
    s = '';
    if isstruct(item) && isfield(item, name) && ischar(item.(name))
        s = item.(name);
    end
end

% -------------------------------------------------------------------------
function v = numberField(item, name, defaultValue)
    v = defaultValue;
    if isstruct(item) && isfield(item, name) && ...
            isnumeric(item.(name)) && isscalar(item.(name)) && ...
            ~isnan(item.(name))
        v = double(item.(name));
    end
end

% -------------------------------------------------------------------------
function v = logicalField(item, name, defaultValue)
    v = defaultValue;
    if isstruct(item) && isfield(item, name)
        value = item.(name);
        if (islogical(value) || isnumeric(value)) && ~isempty(value)
            v = logical(value(1));
        end
    end
end
