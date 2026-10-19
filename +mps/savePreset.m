function presets = savePreset(sourceFile, name, params)
%SAVEPRESET Add or replace a named parameter set.
%
%   presets = mps.savePreset(sourceFile, name, params)
%
%   Reads <script>_presets.json, replaces the preset with the same name (or
%   appends a new one) using the current use / newValue / locked state of
%   params, writes the file back and returns the updated presets array.

    name = strtrim(char(name));
    if isempty(name)
        error('mps:savePreset:emptyName', '参数集名称不能为空。');
    end

    presets = mps.readPresets(sourceFile);
    entry = struct();
    entry.name = name;
    entry.created = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    entry.note = '';
    entry.values = paramsToValues(params);

    idx = find(strcmp({presets.name}, name), 1);
    if isempty(idx)
        presets(end+1) = entry;
    else
        presets(idx) = entry;
    end
    mps.writePresets(sourceFile, presets);
end

% -------------------------------------------------------------------------
function values = paramsToValues(params)
    values = struct('id', {}, 'name', {}, 'line', {}, 'value', {}, ...
        'newValue', {}, 'use', {}, 'locked', {}, 'description', {}, 'unit', {});
    for k = 1:numel(params)
        p = params(k);
        locked = false;
        description = '';
        unit = '';
        if isfield(p, 'locked'), locked = logical(p.locked); end
        if isfield(p, 'description'), description = p.description; end
        if isfield(p, 'unit'), unit = p.unit; end
        values(end+1) = struct( ...
            'id', p.id, 'name', p.name, 'line', p.line, ...
            'value', p.value, 'newValue', p.newValue, ...
            'use', logical(p.use), 'locked', locked, ...
            'description', description, 'unit', unit); %#ok<AGROW>
    end
end
