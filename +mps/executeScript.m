function out = executeScript(scriptPath, maxVariableMB, maxTotalMB)
%EXECUTESCRIPT Run a script in an isolated function workspace.
%
%   The script is executed with run() inside this function.  Variables
%   created by the script stay in this function's workspace and are copied
%   into a struct before returning.  A "clear all" in the script therefore
%   does not clear the caller's workspace or the app.
%
%   Optional maxVariableMB / maxTotalMB control the workspace capture budget
%   (see mps.captureWorkspace).  The capture is done by mps.captureWorkspace,
%   which reads the caller workspace with evalin.  The helper's loop
%   variables therefore cannot overwrite user variables such as k or m.

    if nargin < 2 || isempty(maxVariableMB)
        maxVariableMB = 100;
    end
    if nargin < 3 || isempty(maxTotalMB)
        maxTotalMB = 512;
    end

    % The script may call "clear", which would delete local variables such
    % as maxVariableMB.  Root appdata survives the script's workspace reset.
    setappdata(0, 'mpsCaptureLimits', [maxVariableMB, maxTotalMB]);

    mpsErrorReport = '';
    try
        mpsScriptPath = scriptPath; %#ok<NASGU>
        run(mpsScriptPath);
    catch err
        mpsErrorReport = getReport(err, 'extended', 'hyperlinks', 'off');
    end

    limits = getappdata(0, 'mpsCaptureLimits');
    if isempty(limits)
        limits = [100, 512];
    end
    data = mps.captureWorkspace(limits(1), limits(2));
    cleanupCaptureLimits();

    if ~exist('mpsErrorReport', 'var')
        mpsErrorReport = '';
    end

    out = struct();
    out.ok = isempty(mpsErrorReport);
    out.error = mpsErrorReport;
    out.data = data;
end

% -------------------------------------------------------------------------
function cleanupCaptureLimits()
    try
        if isappdata(0, 'mpsCaptureLimits')
            rmappdata(0, 'mpsCaptureLimits');
        end
    catch
    end
end
