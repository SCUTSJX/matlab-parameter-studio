function [values, meta] = loadRunParameters(runPath)
%LOADRUNPARAMETERS Read parameters.json from a historical run.
%
%   [values, meta] = mps.loadRunParameters(runPath)
%
%   values is a struct array compatible with mps.applyPreset:
%       id, name, line, value, newValue, use, locked, description, unit
%
%   meta contains the run.json record when available (sourceFile, created,
%   ok, error, elapsedSeconds, ...).

    values = emptyValues();
    meta = struct('sourceFile', '', 'created', '', 'ok', NaN, 'error', '');
    if isempty(runPath) || ~isfolder(runPath)
        error('mps:loadRunParameters:missingFolder', ...
            '运行目录不存在：%s', runPath);
    end

    metaPath = fullfile(runPath, 'run.json');
    if isfile(metaPath)
        try
            candidate = jsondecode(fileread(metaPath));
            if isstruct(candidate)
                meta = candidate;
            end
        catch err
            mps.logWarning('读取运行元数据', err);
        end
    end

    paramsPath = fullfile(runPath, 'parameters.json');
    if ~isfile(paramsPath)
        error('mps:loadRunParameters:missingParameters', ...
            '这次运行没有 parameters.json，无法载入参数：%s', runPath);
    end

    try
        data = jsondecode(fileread(paramsPath));
    catch err
        error('mps:loadRunParameters:invalidJson', ...
            '无法读取参数记录：%s\n%s', paramsPath, err.message);
    end
    if iscell(data)
        data = [data{:}];
    end
    if ~isstruct(data)
        return;
    end

    for k = 1:numel(data)
        r = data(k);
        line = numberField(r, 'line', NaN);
        values(end+1) = struct( ...
            'id', charField(r, 'id'), ...
            'name', charField(r, 'name'), ...
            'line', line, ...
            'value', valueField(r, 'value'), ...
            'newValue', valueField(r, 'newValue'), ...
            'use', logicalField(r, 'use', true), ...
            'locked', logicalField(r, 'locked', false), ...
            'description', charField(r, 'description'), ...
            'unit', charField(r, 'unit')); %#ok<AGROW>
    end
end

% -------------------------------------------------------------------------
function values = emptyValues()
    values = struct('id', {}, 'name', {}, 'line', {}, 'value', {}, ...
        'newValue', {}, 'use', {}, 'locked', {}, 'description', {}, ...
        'unit', {});
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
function v = numberField(item, name, defaultValue)
    v = defaultValue;
    if ~isstruct(item) || ~isfield(item, name)
        return;
    end
    value = item.(name);
    if isnumeric(value) && isscalar(value) && ~isnan(value)
        v = double(value);
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
