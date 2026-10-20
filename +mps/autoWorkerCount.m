function n = autoWorkerCount(scenarios, requested, maxCap)
%AUTOWORKERCOUNT Choose a conservative worker count for a job.
%
%   n = mps.autoWorkerCount(scenarios, requested, maxCap)
%
%   requested = 0 means auto: cap at maxCap (default 4) and by available
%   memory/CPU.  A positive requested value is respected but never exceeds
%   the number of scenarios.

    if nargin < 3 || isempty(maxCap)
        maxCap = 4;
    end
    scenarios = max(1, double(scenarios));
    if nargin >= 2 && requested > 0
        n = min(double(requested), scenarios);
        return;
    end

    try
        cores = feature('numcores');
    catch
        cores = 4;
    end
    if isempty(cores) || ~isnumeric(cores) || cores < 1
        cores = 4;
    end

    try
        mem = memory;
        availableGB = mem.MemAvailableAllArrays / 1024^3;
    catch
        availableGB = 2;
    end
    byMemory = max(1, floor(availableGB / 1.5));
    n = min([maxCap, scenarios, max(1, cores), byMemory]);
    n = max(1, n);
end
