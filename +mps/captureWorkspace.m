function data = captureWorkspace()
%CAPTUREWORKSPACE Copy the caller's variables without touching its workspace.
%
%   This helper is called immediately after run() inside mps.executeScript.
%   It uses evalin('caller', ...) so that its own loop variables (k, name,
%   etc.) cannot overwrite variables created by the user's script.  This is
%   important: a script may legitimately define a parameter named "k".

    vars = evalin('caller', 'whos');
    data = struct();
    for k = 1:numel(vars)
        name = vars(k).name;
        if any(strcmp(name, {'mpsScriptPath', 'mpsErrorReport', 'ans'}))
            continue;
        end
        cls = vars(k).class;
        if startsWith(cls, 'matlab.ui.') || startsWith(cls, 'matlab.graphics.')
            continue;
        end
        if vars(k).bytes > 100e6
            continue;
        end
        try
            data.(name) = evalin('caller', name);
        catch
        end
    end
end
