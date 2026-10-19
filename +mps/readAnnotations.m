function anns = readAnnotations(jsonPath)
%READANNOTATIONS Read an annotation JSON produced by an AI or by hand.
%
%   anns = mps.readAnnotations(jsonPath)
%
%   Supported shapes:
%
%   1. The template written by mps.writeAnnotationTemplate:
%          {"schema":"mps.annotations.v1", "parameters":[ {...}, ... ]}
%
%   2. A bare array of annotation objects:
%          [ {"name":"m","description":"质量","unit":"kg"}, ... ]
%
%   3. A compact name map (easiest for an AI to produce):
%          {"m": "质量", "k": {"description":"刚度","unit":"N/m"}}
%
%   Returned struct array fields: id, name, line, description, unit.

    if ~isfile(jsonPath)
        error('mps:readAnnotations:fileNotFound', '找不到注释文件：%s', jsonPath);
    end
    raw = fileread(jsonPath);
    try
        data = jsondecode(raw);
    catch err
        error('mps:readAnnotations:badJson', ...
            'JSON 解析失败：%s\n%s', err.message, jsonPath);
    end

    anns = emptyAnnotations();
    items = collectItems(data);
    for k = 1:numel(items)
        a = normalizeItem(items{k});
        if isempty(a.id) && isempty(a.name) && isempty(a.description)
            continue;
        end
        anns(end+1) = a; %#ok<AGROW>
    end
end

% -------------------------------------------------------------------------
function anns = emptyAnnotations()
    anns = struct('id', {}, 'name', {}, 'line', {}, ...
        'description', {}, 'unit', {});
end

% -------------------------------------------------------------------------
function items = collectItems(data)
    items = {};
    if isempty(data)
        return;
    end
    if iscell(data)
        items = data(:)';
        return;
    end
    if ~isstruct(data)
        return;
    end

    if numel(data) > 1
        for k = 1:numel(data)
            items{end+1} = data(k); %#ok<AGROW>
        end
        return;
    end

    % A single struct: it may be a wrapper with a parameters field, a single
    % annotation, or a name -> annotation map.
    if isfield(data, 'parameters')
        inner = data.parameters;
        if iscell(inner)
            items = inner(:)';
        elseif isstruct(inner)
            for k = 1:numel(inner)
                items{end+1} = inner(k); %#ok<AGROW>
            end
        end
        return;
    end

    if looksLikeAnnotation(data)
        items = {data};
        return;
    end

    fns = fieldnames(data);
    for k = 1:numel(fns)
        name = fns{k};
        value = data.(name);
        item = struct();
        item.name = name;
        if ischar(value) || isstring(value)
            item.description = char(value);
        elseif isstruct(value)
            item = value;
            if ~isfield(item, 'name') || isempty(item.name)
                item.name = name;
            end
        elseif iscell(value) && ~isempty(value) && ...
                (ischar(value{1}) || isstring(value{1}))
            item.description = char(value{1});
        else
            item.description = '';
        end
        items{end+1} = item; %#ok<AGROW>
    end
end

% -------------------------------------------------------------------------
function tf = looksLikeAnnotation(s)
    tf = isstruct(s) && (isfield(s, 'name') || isfield(s, 'id') || ...
        isfield(s, 'description') || isfield(s, 'desc') || ...
        isfield(s, 'comment'));
end

% -------------------------------------------------------------------------
function a = normalizeItem(item)
    a = struct('id', '', 'name', '', 'line', NaN, ...
        'description', '', 'unit', '');
    if ~isstruct(item)
        return;
    end
    a.id = charField(item, {'id'});
    a.name = charField(item, {'name', 'parameter', 'variable', 'var'});
    a.line = numericField(item, {'line', 'lineNo', 'lineNumber'});
    a.description = charField(item, ...
        {'description', 'desc', 'comment', 'meaning', 'label', 'note'});
    a.unit = charField(item, {'unit', 'units'});
    if isempty(a.description) && isfield(item, 'comment')
        a.description = charField(item, {'comment'});
    end
end

% -------------------------------------------------------------------------
function s = charField(item, names)
    s = '';
    for k = 1:numel(names)
        if ~isfield(item, names{k})
            continue;
        end
        v = item.(names{k});
        if ischar(v)
            s = v;
            return;
        elseif isstring(v) && isscalar(v)
            s = char(v);
            return;
        elseif iscell(v) && ~isempty(v) && (ischar(v{1}) || isstring(v{1}))
            s = char(v{1});
            return;
        end
    end
end

% -------------------------------------------------------------------------
function v = numericField(item, names)
    v = NaN;
    for k = 1:numel(names)
        if ~isfield(item, names{k})
            continue;
        end
        x = item.(names{k});
        if isnumeric(x) && isscalar(x)
            v = double(x);
            return;
        end
    end
end
