function [params, stats] = applyPreset(params, preset)
%APPLYPRESET Apply a saved parameter set to the current parameter list.
%
%   [params, stats] = mps.applyPreset(params, preset)
%
%   Matching priority (same as annotations):
%       1. exact id
%       2. name + line
%       3. unique name
%
%   For every match the preset's use / newValue / locked state is applied.
%   A locked entry always keeps the script's original value.

    stats = struct('matched', 0, 'ambiguous', 0, 'unmatched', 0);
    if isempty(params) || ~isstruct(preset) || ~isfield(preset, 'values')
        return;
    end
    if ~isfield(params, 'locked')
        [params.locked] = deal(false);
    end
    values = preset.values;

    for k = 1:numel(values)
        v = values(k);
        if isempty(v.id) && isempty(v.name)
            continue;
        end

        target = 0;
        if ~isempty(v.id)
            idxs = find(strcmp({params.id}, v.id));
            if numel(idxs) == 1
                target = idxs;
            end
        end
        if target == 0 && ~isempty(v.name) && ~isnan(v.line)
            idxs = find(strcmp({params.name}, v.name) & [params.line] == v.line);
            if numel(idxs) == 1
                target = idxs;
            end
        end
        if target == 0 && ~isempty(v.name)
            idxs = find(strcmp({params.name}, v.name));
            if numel(idxs) == 1
                target = idxs;
            elseif numel(idxs) > 1
                stats.ambiguous = stats.ambiguous + 1;
                continue;
            end
        end

        if target == 0
            stats.unmatched = stats.unmatched + 1;
            continue;
        end

        params(target).use = logical(v.use);
        if isfield(params, 'ignored') && params(target).ignored
            params(target).use = false;
        end
        if v.locked
            params(target).locked = true;
            params(target).newValue = params(target).value;
        else
            params(target).locked = false;
            if ~isempty(v.newValue)
                params(target).newValue = v.newValue;
            end
        end
        params(target).isChanged = ~strcmp( ...
            strtrim(params(target).value), strtrim(params(target).newValue));
        stats.matched = stats.matched + 1;
    end
end
