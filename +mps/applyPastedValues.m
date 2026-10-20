function [params, stats] = applyPastedValues(params, indices, values)
%APPLYPASTEDVALUES Fill selected parameters with a list of new values.
%
%   [params, stats] = mps.applyPastedValues(params, indices, values)
%
%   values is a cell array of numeric expressions, one per target row.
%   Locked parameters are skipped but still consume their clipboard row.

    stats = struct('changed', 0, 'skippedLocked', 0, ...
        'skippedInvalid', 0, 'skippedNonNumeric', 0);
    if isempty(params)
        return;
    end
    if ischar(values) || isstring(values)
        values = cellstr(values);
    end
    indices = double(indices(:)');
    if numel(values) ~= numel(indices)
        error('mps:applyPastedValues:countMismatch', ...
            mps.tr('剪贴板有 %d 个值，但目标有 %d 行。', ...
            'The clipboard has %d values but the target has %d rows.'), ...
            numel(values), numel(indices));
    end

    for j = 1:numel(indices)
        idx = indices(j);
        if idx < 1 || idx > numel(params)
            continue;
        end
        value = strtrim(char(values{j}));
        [ok, ~] = mps.validateValue(value);
        if ~ok || isempty(value)
            stats.skippedInvalid = stats.skippedInvalid + 1;
            error('mps:applyPastedValues:invalidValue', ...
                mps.tr('第 %d 行的值无效：%s', ...
                'Invalid value on row %d: %s'), j, value);
        end
        if isfield(params(idx), 'locked') && logical(params(idx).locked)
            stats.skippedLocked = stats.skippedLocked + 1;
            continue;
        end
        oldValue = params(idx).newValue;
        params(idx).newValue = value;
        params(idx).isChanged = ~strcmp( ...
            strtrim(params(idx).value), strtrim(value));
        if ~strcmp(strtrim(oldValue), value)
            stats.changed = stats.changed + 1;
        end
    end
end
