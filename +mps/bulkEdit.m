function [params, stats] = bulkEdit(params, indices, op, value)
%BULKEDIT Apply one batch operation to several parameters.
%
%   [params, stats] = mps.bulkEdit(params, indices, op, value)
%
%   op is one of:
%       'set'      set newValue to value (numeric expression)
%       'scale'    newValue = newValue * value
%       'offset'   newValue = newValue + value
%       'reset'    newValue = original script value
%       'useon'    mark parameters as used
%       'useoff'   mark parameters as unused
%       'lock'     pin parameters to their original value
%       'unlock'   release parameters
%
%   Locked parameters are skipped by set/scale/offset.  stats reports how
%   many entries changed and why some were skipped.

    if nargin < 4
        value = '';
    end
    stats = struct('changed', 0, 'skippedLocked', 0, ...
        'skippedInvalid', 0, 'skippedNonNumeric', 0);
    if isempty(params)
        return;
    end

    op = lower(strtrim(char(op)));
    value = strtrim(char(value));
    indices = unique(double(indices(:)'));
    indices = indices(indices >= 1 & indices <= numel(params));

    switch op
        case 'set'
            [ok, ~] = mps.validateValue(value);
            if ~ok || isempty(value)
                error('mps:bulkEdit:invalidValue', ...
                    '新的参数值不是有效的数值表达式：%s', value);
            end
            for k = indices
                if isLocked(params(k))
                    stats.skippedLocked = stats.skippedLocked + 1;
                    continue;
                end
                [params(k), didChange] = setNewValue(params(k), value);
                if didChange
                    stats.changed = stats.changed + 1;
                end
            end

        case {'scale', 'offset'}
            [ok, operand] = mps.validateValue(value);
            if ~ok || ~isnumeric(operand) || ~isscalar(operand) || ...
                    ~isreal(operand) || ~isfinite(operand)
                error('mps:bulkEdit:invalidOperand', ...
                    '系数/偏移量必须是有限实数：%s', value);
            end
            for k = indices
                if isLocked(params(k))
                    stats.skippedLocked = stats.skippedLocked + 1;
                    continue;
                end
                [okCurrent, current] = mps.validateValue(params(k).newValue);
                if ~okCurrent || ~isnumeric(current) || ...
                        ~isscalar(current) || ~isreal(current)
                    stats.skippedNonNumeric = stats.skippedNonNumeric + 1;
                    continue;
                end
                if strcmp(op, 'scale')
                    updated = current * operand;
                else
                    updated = current + operand;
                end
                [params(k), didChange] = setNewValue(params(k), ...
                    num2str(updated, '%.10g'));
                if didChange
                    stats.changed = stats.changed + 1;
                end
            end

        case 'reset'
            for k = indices
                original = valueOf(params(k), 'value');
                if ~strcmp(strtrim(params(k).newValue), strtrim(original))
                    stats.changed = stats.changed + 1;
                end
                params(k).newValue = original;
                params(k).isChanged = false;
            end

        case {'useon', 'useoff'}
            newUse = strcmp(op, 'useon');
            for k = indices
                if logical(params(k).use) ~= newUse
                    params(k).use = newUse;
                    stats.changed = stats.changed + 1;
                end
            end

        case {'lock', 'unlock'}
            newLock = strcmp(op, 'lock');
            for k = indices
                if logical(params(k).locked) ~= newLock
                    params(k).locked = newLock;
                    if newLock
                        params(k).newValue = valueOf(params(k), 'value');
                        params(k).isChanged = false;
                    else
                        params(k).isChanged = ~strcmp( ...
                            strtrim(params(k).value), ...
                            strtrim(params(k).newValue));
                    end
                    stats.changed = stats.changed + 1;
                end
            end

        otherwise
            error('mps:bulkEdit:unknownOperation', ...
                '未知的批量操作：%s', op);
    end
end

% -------------------------------------------------------------------------
function [p, didChange] = setNewValue(p, value)
    oldValue = '';
    if isfield(p, 'newValue')
        oldValue = char(p.newValue);
    end
    p.newValue = value;
    p.isChanged = ~strcmp(strtrim(p.value), strtrim(value));
    didChange = ~strcmp(strtrim(oldValue), strtrim(value));
end

% -------------------------------------------------------------------------
function tf = isLocked(p)
    tf = isfield(p, 'locked') && logical(p.locked);
end

% -------------------------------------------------------------------------
function s = valueOf(p, name)
    if isfield(p, name)
        s = char(p.(name));
    else
        s = '';
    end
end
