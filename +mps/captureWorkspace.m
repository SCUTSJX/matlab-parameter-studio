function data = captureWorkspace(maxVariableMB, maxTotalMB)
%CAPTUREWORKSPACE Copy the caller's variables without touching its workspace.
%
%   data = mps.captureWorkspace()
%   data = mps.captureWorkspace(maxVariableMB, maxTotalMB)
%
%   The helper is called immediately after run() inside mps.executeScript.
%   It uses evalin('caller', ...) so its own loop variables cannot overwrite
%   variables created by the user's script.
%
%   Defaults: 100 MB per variable and 512 MB total.  Variables beyond the
%   budget are skipped and a warning is written to the run log, which keeps
%   large simulation workspaces from exhausting memory.

    if nargin < 1 || isempty(maxVariableMB)
        maxVariableMB = 100;
    end
    if nargin < 2 || isempty(maxTotalMB)
        maxTotalMB = 512;
    end
    maxVarBytes = maxVariableMB * 1024^2;
    maxTotalBytes = maxTotalMB * 1024^2;

    vars = evalin('caller', 'whos');
    data = struct();
    totalBytes = 0;
    skipped = {};

    for k = 1:numel(vars)
        name = vars(k).name;
        if any(strcmp(name, {'mpsScriptPath', 'mpsErrorReport', 'ans', ...
                'maxVariableMB', 'maxTotalMB', 'limits'}))
            continue;
        end
        cls = vars(k).class;
        if startsWith(cls, 'matlab.ui.') || ...
                startsWith(cls, 'matlab.graphics.') || ...
                strcmp(cls, 'function_handle')
            continue;
        end
        bytes = vars(k).bytes;
        if bytes > maxVarBytes || totalBytes + bytes > maxTotalBytes
            skipped{end+1} = name; %#ok<AGROW>
            continue;
        end
        try
            data.(name) = evalin('caller', name);
            totalBytes = totalBytes + bytes;
        catch
        end
    end

    if ~isempty(skipped)
        shown = skipped(1:min(5, numel(skipped)));
        warning('mps:captureWorkspace:limit', ...
            ['已跳过 %d 个大变量（单变量上限 %g MB，总上限 %g MB）：%s%s'], ...
            numel(skipped), maxVariableMB, maxTotalMB, ...
            strjoin(shown, ', '), ifelse(numel(skipped) > 5, ' ...', ''));
    end
end

% -------------------------------------------------------------------------
function s = ifelse(cond, a, b)
    if cond
        s = a;
    else
        s = b;
    end
end
