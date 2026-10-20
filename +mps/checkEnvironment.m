function info = checkEnvironment(root)
%CHECKENVIRONMENT Inspect the local MATLAB environment without running code.
%
%   info = mps.checkEnvironment()
%
%   This is a local prerequisite check.  It does not contact the network and
%   does not execute project scripts.

    if nargin < 1 || isempty(root)
        root = fileparts(fileparts(mfilename('fullpath')));
    end
    info = struct();
    info.root = char(root);
    info.matlabVersion = version;
    info.release = version('-release');
    info.mpsVersion = mps.version();
    info.hasPCT = license('test', 'Distrib_Computing_Toolbox');
    info.demoFile = fullfile(info.root, 'demo', 'demo_simulation.m');
    info.demoExists = isfile(info.demoFile);
    info.tempWritable = false;
    info.messages = {};

    if verLessThan('matlab', '9.12')
        info.messages{end+1} = ...
            'MATLAB R2022a or newer is recommended.';
    end
    if ~info.demoExists
        info.messages{end+1} = 'Demo script is missing.';
    end
    try
        probe = [tempname, '.mps-probe'];
        fid = fopen(probe, 'w');
        if fid >= 0
            fclose(fid);
            delete(probe);
            info.tempWritable = true;
        end
    catch
        % 探测失败按“临时目录不可写”处理，下面统一提示
    end
    if ~info.tempWritable
        info.messages{end+1} = 'Temporary directory is not writable.';
    end
    required = {'uifigure', 'uipanel', 'uitable', 'exportgraphics', ...
        'jsonencode', 'jsondecode', 'uiprogressdlg'};
    info.missing = {};
    for k = 1:numel(required)
        if exist(required{k}, 'file') == 0 && ...
                exist(required{k}, 'builtin') ~= 5
            info.missing{end+1} = required{k}; %#ok<AGROW>
        end
    end
    if ~isempty(info.missing)
        info.messages{end+1} = ['Missing functions: ' ...
            strjoin(info.missing, ', ')];
    end
    if ~info.hasPCT
        info.messages{end+1} = ...
            'Parallel Computing Toolbox not found; parallel sweep and background runs are disabled.';
    end
    info.ok = info.demoExists && info.tempWritable && ...
        isempty(info.missing) && ~verLessThan('matlab', '9.12');
end
