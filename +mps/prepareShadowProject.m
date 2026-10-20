function shadowRoot = prepareShadowProject(projectRoot)
%PREPARESHADOWPROJECT Reuse a temporary project copy inside one process.
%
%   The first call copies code and inputs; later calls synchronize changed
%   and deleted files.  A persistent map keeps one shadow per project per
%   MATLAB process (including each parallel worker).  Shadow folders use a
%   stable mps_shadow_ prefix so mps.cleanupShadowProjects can find them.

    persistent shadows
    if isempty(shadows)
        shadows = containers.Map('KeyType', 'char', 'ValueType', 'char');
    end
    key = char(projectRoot);
    if isKey(shadows, key) && isfolder(shadows(key))
        shadowRoot = shadows(key);
    else
        % Parallel workers on one machine share tempdir.  Including the
        % process id keeps each worker's shadow independent, otherwise one
        % worker's sync/rewrite would race another worker's running copy.
        shadowRoot = fullfile(tempdir, ...
            sprintf('mps_shadow_%s_%d', shortHash(key), feature('getpid')));
        if isfolder(shadowRoot)
            try
                rmdir(shadowRoot, 's');
            catch err
                mps.logWarning('重建项目影子目录', err);
            end
        end
        mkdir(shadowRoot);
        mps.copyProjectTree(projectRoot, shadowRoot);
        shadows(key) = shadowRoot;
    end
    touchFolder(shadowRoot);
    mps.syncProjectTree(projectRoot, shadowRoot);
end

% -------------------------------------------------------------------------
function key = shortHash(text)
    h = uint32(2166136261);
    for k = 1:numel(text)
        h = bitxor(h, uint32(double(text(k))));
        h = uint32(mod(double(h) * 16777619, 2^32));
    end
    key = sprintf('%08x', h);
end

% -------------------------------------------------------------------------
function touchFolder(path)
    try
        marker = fullfile(path, '.mps_touch');
        fid = fopen(marker, 'w');
        if fid >= 0
            fprintf(fid, '%s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS.FFF'));
            fclose(fid);
        end
    catch err
        mps.logWarning('更新影子目录时间戳', err, 'Silent', true);
    end
end
