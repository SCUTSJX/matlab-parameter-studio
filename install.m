function install(varargin)
%INSTALL Add MATLAB Parameter Studio to the MATLAB path.
%
%   install              add for the current session
%   install('Save')      add and persist with savepath
%
%   Then run MatlabParameterStudio from any folder.

    savePath = false;
    for k = 1:numel(varargin)
        if strcmpi(char(varargin{k}), 'Save')
            savePath = true;
        end
    end

    if verLessThan('matlab', '9.15')   % R2023b
        warning('mps:install:oldMatlab', ...
            ['MATLAB Parameter Studio targets R2023b or newer. ' ...
             'This MATLAB release may not support every UI feature.']);
    end

    root = fileparts(mfilename('fullpath'));
    addpath(root);
    fprintf('MATLAB Parameter Studio %s added to path:\n  %s\n', ...
        mps.version(), root);

    if savePath
        try
            savepath;
            fprintf('Path saved. You can now call MatlabParameterStudio from any folder.\n');
        catch err
            warning('mps:install:savepath', ...
                'Could not save the MATLAB path: %s', err.message);
        end
    else
        fprintf(['This is for the current MATLAB session only. ' ...
                 'Run install(''Save'') to persist it.\n']);
    end
end
