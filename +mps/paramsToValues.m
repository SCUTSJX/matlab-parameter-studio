function values = paramsToValues(params)
%PARAMSTOVALUES Convert scan parameters to the preset/session value format.

    values = struct('id', {}, 'name', {}, 'line', {}, 'value', {}, ...
        'newValue', {}, 'use', {}, 'locked', {}, 'description', {}, ...
        'unit', {});
    for k = 1:numel(params)
        p = params(k);
        locked = false;
        description = '';
        unit = '';
        if isfield(p, 'locked'), locked = logical(p.locked); end
        if isfield(p, 'description'), description = char(p.description); end
        if isfield(p, 'unit'), unit = char(p.unit); end
        values(end+1) = struct( ...
            'id', char(p.id), 'name', char(p.name), 'line', p.line, ...
            'value', char(p.value), 'newValue', char(p.newValue), ...
            'use', logical(p.use), 'locked', locked, ...
            'description', description, 'unit', unit); %#ok<AGROW>
    end
end
