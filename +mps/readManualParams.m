function params = readManualParams(sourceFile)
%READMANUALPARAMS Load user-added parameters from <source>_manual.json.

    params = struct([]);
    path = mps.manualParamsPath(sourceFile);
    if ~isfile(path)
        return;
    end
    try
        raw = jsondecode(fileread(path));
        if iscell(raw)
            % Mixed-type arrays must degrade gracefully, not crash.
            raw = raw(cellfun(@isstruct, raw));
            raw = [raw{:}];
        end
    catch err
        mps.logWarning('读取手动参数', err);
        return;
    end
    if ~isstruct(raw)
        return;
    end
    for k = 1:numel(raw)
        r = raw(k);
        name = fieldChar(r, 'name');
        value = fieldChar(r, 'newValue');
        if isempty(value)
            value = fieldChar(r, 'value');
        end
        if isempty(name) || ~isvarname(name)
            continue;
        end
        try
            p = mps.makeManualParam(sourceFile, name, value, ...
                fieldChar(r, 'description'), fieldChar(r, 'unit'));
        catch err
            mps.logWarning(sprintf('跳过无效手动参数 %s', name), err);
            continue;
        end
        if isfield(r, 'use') && (islogical(r.use) || isnumeric(r.use))
            p.use = logical(r.use(1));
        end
        if isfield(r, 'locked') && (islogical(r.locked) || isnumeric(r.locked))
            p.locked = logical(r.locked(1));
        end
        p.isChanged = ~strcmp(strtrim(p.value), strtrim(p.newValue));
        params = [params, p]; %#ok<AGROW>
    end
end

% -------------------------------------------------------------------------
function s = fieldChar(item, name)
    s = '';
    if ~isstruct(item) || ~isfield(item, name)
        return;
    end
    v = item.(name);
    if ischar(v)
        s = v;
    elseif isstring(v) && isscalar(v)
        s = char(v);
    elseif isnumeric(v) || islogical(v)
        s = num2str(v);
    end
end
