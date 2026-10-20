function presets = readPresets(sourceFile)
%READPRESETS Load named parameter sets saved next to a script.
%
%   presets = mps.readPresets(sourceFile)
%
%   Returns a struct array with fields:
%       name, created, note, values
%   where values is a struct array with fields:
%       id, name, line, value, newValue, use, locked, description, unit

    presets = emptyPresets();
    p = mps.presetsPath(sourceFile);
    if ~isfile(p)
        return;
    end
    try
        data = jsondecode(fileread(p));
    catch err
        mps.logWarning(mps.tr('读取参数集', 'Read parameter presets'), err);
        return;
    end
    try
        if ~isstruct(data) || ~isfield(data, 'presets')
            return;
        end
        items = data.presets;
        if iscell(items)
            % Mixed-type arrays (hand-edited or AI-generated files) must be
            % ignored gracefully, not crash the caller.
            items = items(cellfun(@isstruct, items));
            items = [items{:}];
        end
        if ~isstruct(items)
            return;
        end
        for k = 1:numel(items)
            item = items(k);
            presets(end+1) = struct( ...
                'name', charField(item, 'name'), ...
                'created', charField(item, 'created'), ...
                'note', charField(item, 'note'), ...
                'values', normalizeValues(item)); %#ok<AGROW>
        end
    catch err
        mps.logWarning(mps.tr('解析参数集', 'Parse parameter presets'), err);
        presets = emptyPresets();
    end
end

% -------------------------------------------------------------------------
function presets = emptyPresets()
    presets = struct('name', {}, 'created', {}, 'note', {}, 'values', {});
end

% -------------------------------------------------------------------------
function values = normalizeValues(item)
    values = struct('id', {}, 'name', {}, 'line', {}, 'value', {}, ...
        'newValue', {}, 'use', {}, 'locked', {}, 'description', {}, 'unit', {});
    if ~isfield(item, 'values')
        return;
    end
    raw = item.values;
    if iscell(raw)
        % Mixed-type arrays (hand-edited files) must not crash the reader.
        raw = raw(cellfun(@isstruct, raw));
        raw = [raw{:}];
    end
    if ~isstruct(raw)
        return;
    end
    for k = 1:numel(raw)
        v = struct();
        v.id = charField(raw(k), 'id');
        v.name = charField(raw(k), 'name');
        v.line = numericField(raw(k), 'line');
        v.value = charField(raw(k), 'value');
        v.newValue = charField(raw(k), 'newValue');
        v.use = logicalField(raw(k), 'use');
        v.locked = logicalField(raw(k), 'locked');
        v.description = charField(raw(k), 'description');
        v.unit = charField(raw(k), 'unit');
        values(end+1) = v; %#ok<AGROW>
    end
end

% -------------------------------------------------------------------------
function s = charField(item, name)
    s = '';
    if isfield(item, name)
        x = item.(name);
        if ischar(x)
            s = x;
        elseif isstring(x) && isscalar(x)
            s = char(x);
        end
    end
end

% -------------------------------------------------------------------------
function v = numericField(item, name)
    v = NaN;
    if isfield(item, name)
        x = item.(name);
        if isnumeric(x) && isscalar(x)
            v = double(x);
        end
    end
end

% -------------------------------------------------------------------------
function v = logicalField(item, name)
    v = false;
    if isfield(item, name)
        x = item.(name);
        if islogical(x) || isnumeric(x)
            v = logical(x(1));
        end
    end
end
