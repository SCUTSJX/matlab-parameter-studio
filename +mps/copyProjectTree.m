function copyProjectTree(sourceRoot, targetRoot)
%COPYPROJECTTREE Copy a project's code and input files to a shadow folder.
%
%   Result/cache folders are intentionally excluded so tuning does not copy
%   hundreds of megabytes of old figures and workspaces.

    excluded = {'运行结果', 'parameter_studio_runs', '绘图数据缓存', ...
        '.git', '__pycache__', '.mps_cache'};
    if ~isfolder(targetRoot)
        mkdir(targetRoot);
    end
    copyLevel(sourceRoot, targetRoot, excluded);
end

% -------------------------------------------------------------------------
function copyLevel(source, target, excluded)
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
            copyLevel(src, dst, excluded);
        else
            try
                copyfile(src, dst);
            catch err
                mps.logWarning(sprintf('复制项目文件 %s', item.name), err);
            end
        end
    end
end
