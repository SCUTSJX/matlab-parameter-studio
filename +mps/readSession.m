function session = readSession(sourceFile)
%READSESSION Load <name>_session.json when it exists.
%
%   session is empty when there is no valid session file.  Otherwise it has
%   fields sourceFile, savedAt, stamp and values.  values uses the same
%   format as mps.readPresets / mps.applyPreset.

    session = struct([]);
    if isempty(sourceFile)
        return;
    end
    path = mps.sessionPath(sourceFile);
    if ~isfile(path)
        return;
    end
    try
        data = jsondecode(fileread(path));
    catch err
        mps.logWarning(mps.tr('读取会话文件', 'Read session file'), err);
        return;
    end
    try
        if ~isstruct(data) || ~isfield(data, 'values')
            return;
        end
        values = normalizeValues(data.values);
        if isempty(values)
            return;
        end
        session = struct( ...
            'sourceFile', charField(data, 'sourceFile'), ...
            'savedAt', charField(data, 'savedAt'), ...
            'stamp', stampField(data), ...
            'values', values);
    catch err
        mps.logWarning(mps.tr('解析会话文件', 'Parse session file'), err);
        session = struct([]);
    end
end

% -------------------------------------------------------------------------
function values = normalizeValues(raw)
    values = struct('id', {}, 'name', {}, 'line', {}, 'value', {}, ...
        'newValue', {}, 'use', {}, 'locked', {}, 'description', {}, ...
        'unit', {});
    if iscell(raw)
        % Mixed-type arrays (hand-edited files) must not crash the reader.
        raw = raw(cellfun(@isstruct, raw));
        raw = [raw{:}];
    end
    if ~isstruct(raw)
        return;
    end
    for k = 1:numel(raw)
        item = raw(k);
        values(end+1) = struct( ...
            'id', charField(item, 'id'), ...
            'name', charField(item, 'name'), ...
            'line', numberField(item, 'line'), ...
            'value', valueField(item, 'value'), ...
            'newValue', valueField(item, 'newValue'), ...
            'use', logicalField(item, 'use', true), ...
            'locked', logicalField(item, 'locked', false), ...
            'description', charField(item, 'description'), ...
            'unit', charField(item, 'unit')); %#ok<AGROW>
    end
end

% -------------------------------------------------------------------------
function stamp = stampField(data)
    stamp = struct();
    if isfield(data, 'stamp') && isstruct(data.stamp)
        stamp = data.stamp;
    end
end

% -------------------------------------------------------------------------
function s = charField(item, name)
    s = '';
    if ~isstruct(item) || ~isfield(item, name)
        return;
    end
    value = item.(name);
    if ischar(value)
        s = value;
    elseif isstring(value) && isscalar(value)
        s = char(value);
    end
end

% -------------------------------------------------------------------------
function s = valueField(item, name)
    s = '';
    if ~isstruct(item) || ~isfield(item, name)
        return;
    end
    value = item.(name);
    if ischar(value)
        s = value;
    elseif isstring(value) && isscalar(value)
        s = char(value);
    elseif isnumeric(value) || islogical(value)
        s = num2str(value);
    end
end

% -------------------------------------------------------------------------
function v = numberField(item, name)
    v = NaN;
    if isstruct(item) && isfield(item, name) && ...
            isnumeric(item.(name)) && isscalar(item.(name))
        v = double(item.(name));
    end
end

% -------------------------------------------------------------------------
function v = logicalField(item, name, defaultValue)
    v = defaultValue;
    if ~isstruct(item) || ~isfield(item, name)
        return;
    end
    value = item.(name);
    if islogical(value) || isnumeric(value)
        if ~isempty(value)
            v = logical(value(1));
        end
    end
end
