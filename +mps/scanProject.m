function params = scanProject(root, varargin)
%SCANPROJECT Scan every .m file under a project root.
%
%   params = mps.scanProject(root)
%
%   Result/cache folders are skipped.  Every parameter keeps its sourceFile,
%   so the table can group/filter by file and the project runner can apply
%   edits to the corresponding shadow copies.

    if nargin < 1 || isempty(root) || ~isfolder(root)
        error('mps:scanProject:missingRoot', '项目目录不存在：%s', char(root));
    end
    excluded = {'运行结果', 'parameter_studio_runs', '绘图数据缓存', ...
        '.git', '__pycache__', '.mps_cache'};

    files = dir(fullfile(root, '**', '*.m'));
    paths = {};
    for k = 1:numel(files)
        p = fullfile(files(k).folder, files(k).name);
        if isExcluded(p, root, excluded)
            continue;
        end
        paths{end+1} = p; %#ok<AGROW>
    end
    paths = sort(paths);

    params = struct([]);
    for k = 1:numel(paths)
        try
            one = mps.scan(paths{k});
        catch err
            mps.logWarning(sprintf('扫描项目文件 %s', paths{k}), err, ...
                'Silent', true);
            continue;
        end
        if isempty(params)
            params = one;
        elseif ~isempty(one)
            params = [params, one]; %#ok<AGROW>
        end
    end
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
