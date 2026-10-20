function stamp = projectStamp(root)
%PROJECTSTAMP Fingerprint all .m files under a project root.
%
%   stamp.signature changes when any scanned source file changes.

    excluded = {'运行结果', 'parameter_studio_runs', '绘图数据缓存', ...
        '.git', '__pycache__', '.mps_cache'};
    stamp = struct('root', char(root), 'signature', '');
    if ~isfolder(root)
        return;
    end
    files = dir(fullfile(root, '**', '*.m'));
    parts = {};
    for k = 1:numel(files)
        file = fullfile(files(k).folder, files(k).name);
        if isExcluded(file, root, excluded)
            continue;
        end
        try
            s = mps.sourceStamp(file);
            parts{end+1} = sprintf('%s|%.10g|%d|%.10g', ...
                file, s.datenum, s.bytes, s.checksum); %#ok<AGROW>
        catch
        end
    end
    stamp.signature = strjoin(sort(parts), ';');
end

% -------------------------------------------------------------------------
function tf = isExcluded(path, root, excluded)
    rel = path;
    prefix = [root filesep];
    if strncmpi(rel, prefix, numel(prefix))
        rel = rel(numel(prefix)+1:end);
    end
    parts = regexp(rel, '[\\/]', 'split');
    tf = any(ismember(parts, excluded));
end
