function shadowRoot = prepareShadowProject(projectRoot)
%PREPARESHADOWPROJECT Reuse a temporary project copy inside one process.
%
%   The first call copies code and inputs; later calls only synchronize
%   changed files.  A persistent map keeps one shadow per project per
%   MATLAB process (including each parallel worker).

    persistent shadows
    if isempty(shadows)
        shadows = containers.Map('KeyType', 'char', 'ValueType', 'char');
    end
    key = char(projectRoot);
    if isKey(shadows, key) && isfolder(shadows(key))
        shadowRoot = shadows(key);
    else
        shadowRoot = tempname;
        mkdir(shadowRoot);
        mps.copyProjectTree(projectRoot, shadowRoot);
        shadows(key) = shadowRoot;
    end
    mps.syncProjectTree(projectRoot, shadowRoot);
end
