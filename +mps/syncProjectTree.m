function syncProjectTree(sourceRoot, targetRoot)
%SYNCPROJECTTREE Synchronize code changes into a reusable shadow project.
%
%   .m files are always refreshed (they may contain parameter edits from a
%   previous scenario); other input files are copied only when their size or
%   timestamp changed.

    excluded = {'运行结果', 'parameter_studio_runs', '绘图数据缓存', ...
        '.git', '__pycache__', '.mps_cache'};
    if ~isfolder(targetRoot)
        mkdir(targetRoot);
    end
    syncLevel(sourceRoot, targetRoot, excluded);
end

% -------------------------------------------------------------------------
function syncLevel(source, target, excluded)
    items = dir(source);
    for k = 1:numel(items)
        item = items(k);
        if strcmp(item.name, '.') || strcmp(item.name, '..')
            continue;
        end
        if any(strcmp(item.name, excluded))
            continue;
        end
        src = fullfile(source, item.name);
        dst = fullfile(target, item.name);
        if item.isdir
            if ~isfolder(dst)
                mkdir(dst);
            end
            syncLevel(src, dst, excluded);
            continue;
        end

        [~, ~, ext] = fileparts(item.name);
        shouldCopy = strcmpi(ext, '.m') || ~isfile(dst);
        if ~shouldCopy
            try
                d = dir(dst);
                shouldCopy = isempty(d) || d(1).bytes ~= item.bytes || ...
                    abs(d(1).datenum - item.datenum) > 1e-8;
            catch
                shouldCopy = true;
            end
        end
        if shouldCopy
            try
                copyfile(src, dst);
            catch
            end
        end
    end
end
