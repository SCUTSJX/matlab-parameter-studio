function [params, stats] = applyAnnotations(params, anns)
%APPLYANNOTATIONS Match annotations to scanned parameters.
%
%   [params, stats] = mps.applyAnnotations(params, anns)
%
%   Matching priority:
%       1. exact id (file|line|column)
%       2. name + line
%       3. unique name
%
%   Matched entries get their description and unit fields updated.
%   stats.matched / stats.ambiguous / stats.unmatched / stats.skipped
%   summarize what happened.  Ambiguous name-only matches are left alone so
%   that duplicated names (for example two switch_time fields on one line)
%   are never guessed.

    if isempty(params)
        stats = struct('matched', 0, 'ambiguous', 0, ...
            'unmatched', 0, 'skipped', 0);
        return;
    end
    if ~isfield(params, 'description')
        [params.description] = deal('');
    end
    if ~isfield(params, 'unit')
        [params.unit] = deal('');
    end

    stats = struct('matched', 0, 'ambiguous', 0, 'unmatched', 0, 'skipped', 0);
    for k = 1:numel(anns)
        a = anns(k);
        if isempty(a.description) && isempty(a.unit)
            stats.skipped = stats.skipped + 1;
            continue;
        end

        target = 0;
        if ~isempty(a.id)
            idxs = find(strcmp({params.id}, a.id));
            if numel(idxs) == 1
                target = idxs;
            end
        end
        if target == 0 && ~isempty(a.name) && ~isnan(a.line)
            idxs = find(strcmp({params.name}, a.name) & ...
                [params.line] == a.line);
            if numel(idxs) == 1
                target = idxs;
            end
        end
        if target == 0 && ~isempty(a.name)
            idxs = find(strcmp({params.name}, a.name));
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
        params(target).description = a.description;
        params(target).unit = a.unit;
        stats.matched = stats.matched + 1;
    end
end
