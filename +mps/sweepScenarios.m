function scenarios = sweepScenarios(names, values, maxCount)
%SWEEPSCENARIOS Build the Cartesian product of several sweep value lists.
%
%   scenarios = mps.sweepScenarios({'k','c'}, {1:2:9, [0.1 0.2]}, 24)
%
%   Returns a struct array with fields:
%       values  - cell array with one value per parameter
%       label   - human-readable text such as "k=5, c=0.2"
%
%   Errors when the number of combinations exceeds maxCount.

    if nargin < 3 || isempty(maxCount)
        maxCount = 24;
    end
    scenarios = struct('values', {}, 'label', {});
    if isempty(values)
        return;
    end
    counts = cellfun(@numel, values);
    if any(counts == 0)
        return;
    end
    total = prod(counts);
    if total > maxCount
        error('mps:sweepScenarios:tooMany', ...
            '扫描组合数 %d 超过上限 %d，请减少取值数量。', total, maxCount);
    end

    idx = ones(1, numel(values));
    for c = 1:total
        combo = cell(1, numel(values));
        parts = cell(1, numel(values));
        for j = 1:numel(values)
            v = values{j}(idx(j));
            combo{j} = v;
            parts{j} = sprintf('%s=%g', names{j}, v);
        end
        scenarios(end+1) = struct('values', {combo}, ...
            'label', {strjoin(parts, ', ')}); %#ok<AGROW>

        % Increment the index: last dimension changes fastest.
        for j = numel(values):-1:1
            idx(j) = idx(j) + 1;
            if idx(j) <= counts(j)
                break;
            end
            idx(j) = 1;
        end
    end
end
