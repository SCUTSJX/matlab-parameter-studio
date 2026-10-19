function out = executeScript(scriptPath)
%EXECUTESCRIPT Run a script in an isolated function workspace.
%
%   The script is executed with run() inside this function.  Variables
%   created by the script stay in this function's workspace and are copied
%   into a struct before returning.  A "clear all" in the script therefore
%   does not clear the caller's workspace or the app.
%
%   The capture is done by mps.captureWorkspace, which reads the caller
%   workspace with evalin.  The helper's loop variables therefore cannot
%   overwrite user variables such as k or m.

    mpsErrorReport = '';
    try
        mpsScriptPath = scriptPath; %#ok<NASGU>
        run(mpsScriptPath);
    catch err
        mpsErrorReport = getReport(err, 'extended', 'hyperlinks', 'off');
    end

    data = mps.captureWorkspace();

    if ~exist('mpsErrorReport', 'var')
        mpsErrorReport = '';
    end

    out = struct();
    out.ok = isempty(mpsErrorReport);
    out.error = mpsErrorReport;
    out.data = data;
end
