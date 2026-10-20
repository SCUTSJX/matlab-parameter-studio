function syncProjectTree(sourceRoot, targetRoot)
%SYNCPROJECTTREE Synchronize code changes into a reusable shadow project.
%
%   .m files are always refreshed (they may contain parameter edits from a
%   previous scenario); other input files are copied only when their size or
%   timestamp changed.  A manifest records the mirrored files so files
%   deleted or renamed in the source project are removed from the shadow
%   without touching generated outputs.

    excluded = {'运行结果', 'parameter_studio_runs', '绘图数据缓存', ...
        '.git', '__pycache__', '.mps_cache'};
    manifestName = '.mps_shadow_manifest.txt';
    if ~isfolder(targetRoot)
        mkdir(targetRoot);
    end

    manifestPath = fullfile(targetRoot, manifestName);
    oldFiles = readManifest(manifestPath);
    newFiles = copyLevel(sourceRoot, targetRoot, '', excluded, ...
        manifestName, {});
    newFiles = sort(unique(newFiles));

    stale = setdiff(oldFiles, newFiles);
    for k = 1:numel(stale)
        rel = strrep(stale{k}, '/', filesep);
        target = fullfile(targetRoot, rel);
        if isfile(target)
            try
                delete(target);
            catch err
                mps.logWarning(mps.tr('删除影子文件 %s', ...
                    'Delete shadow file %s', stale{k}), err);
            end
        end
    end
    writeManifest(manifestPath, newFiles);
    pruneEmptyFolders(targetRoot, targetRoot, excluded);
end

% -------------------------------------------------------------------------
function files = copyLevel(source, target, relBase, excluded, manifestName, files)
    items = dir(source);
    for k = 1:numel(items)
        item = items(k);
        if strcmp(item.name, '.') || strcmp(item.name, '..') || ...
                strcmp(item.name, manifestName) || ...
                strcmp(item.name, '.mps_touch')
            continue;
        end
        if any(strcmp(item.name, excluded))
            continue;
        end
        rel = item.name;
        if ~isempty(relBase)
            rel = [relBase '/' item.name];
        end
        src = fullfile(source, item.name);
        dst = fullfile(target, item.name);
        if item.isdir
            if ~isfolder(dst)
                mkdir(dst);
            end
            files = copyLevel(src, dst, rel, excluded, manifestName, files);
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
            catch err
                mps.logWarning(mps.tr('同步项目文件 %s', ...
                    'Sync project file %s', rel), err);
                files{end+1} = rel; %#ok<AGROW>
                continue;
            end
        end
        files{end+1} = rel; %#ok<AGROW>
    end
end

% -------------------------------------------------------------------------
function files = readManifest(path)
    files = {};
    if ~isfile(path)
        return;
    end
    try
        txt = fileread(path);
        files = regexp(txt, '\r?\n', 'split');
        files = files(~cellfun(@isempty, files));
        files = cellfun(@strtrim, files, 'UniformOutput', false);
    catch err
        mps.logWarning(mps.tr('读取影子目录清单', ...
            'Read shadow folder manifest'), err);
        files = {};
    end
end

% -------------------------------------------------------------------------
function writeManifest(path, files)
    try
        fid = fopen(path, 'w', 'n', 'UTF-8');
        if fid < 0
            error('mps:syncProjectTree:manifest', mps.tr( ...
                '无法写入清单：%s', 'Cannot write manifest: %s'), path);
        end
        cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
        for k = 1:numel(files)
            fprintf(fid, '%s\n', files{k});
        end
    catch err
        mps.logWarning(mps.tr('写入影子目录清单', ...
            'Write shadow folder manifest'), err);
    end
end

% -------------------------------------------------------------------------
function pruneEmptyFolders(root, current, excluded)
    items = dir(current);
    for k = 1:numel(items)
        item = items(k);
        if ~item.isdir || strcmp(item.name, '.') || ...
                strcmp(item.name, '..') || any(strcmp(item.name, excluded))
            continue;
        end
        child = fullfile(current, item.name);
        pruneEmptyFolders(root, child, excluded);
        if ~strcmpi(child, root)
            try
                contents = dir(child);
                contents = contents(~ismember({contents.name}, {'.', '..'}));
                if isempty(contents)
                    rmdir(child);
                end
            catch
                % 目录非空或正被占用时保留
            end
        end
    end
end
