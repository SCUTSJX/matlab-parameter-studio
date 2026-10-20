function run_tests()
%RUN_TESTS Self-contained checks for MATLAB Parameter Studio.
%
%   Run from MATLAB:
%       run_tests
%
%   Test bodies live in test_*.m scripts so each feature area can be run
%   independently while sharing the same fixture in this workspace.

    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'tests'));
    fprintf('== MATLAB Parameter Studio tests ==\n');

    % Keep the test run quiet: figures created by the demo scripts are
    % invisible, and any figures created during the tests are closed on
    % exit (the caller's existing figures are left alone).
    oldVis = get(groot, 'defaultFigureVisible');
    set(groot, 'defaultFigureVisible', 'off');
    beforeFigs = findall(groot, 'Type', 'figure');
    hadPool = ~isempty(gcp('nocreate'));
    cleanupObj = onCleanup(@() cleanupTestFigures(oldVis, beforeFigs)); %#ok<NASGU>
    poolCleanup = onCleanup(@() stopTestPool(hadPool)); %#ok<NASGU>

    demo = fullfile(root, 'demo', 'demo_simulation.m');
    assert(isfile(demo), 'demo script missing');

    test_detection;
    test_execution;
    test_scanning;
    test_sweep;
    test_bulk;
    test_history;
    test_session;
    test_executors;
    test_project;
    test_parallel;
    test_app;
    test_cleanup;

    fprintf('ALL TESTS PASSED\n');
end

% -------------------------------------------------------------------------
function stopTestPool(hadPool)
    if hadPool
        return;   % do not stop a pool the caller already had open
    end
    try
        pool = gcp('nocreate');
        if ~isempty(pool)
            delete(pool);
        end
    catch
    end
end

% -------------------------------------------------------------------------
function cleanupTestFigures(oldVis, beforeFigs)
    set(groot, 'defaultFigureVisible', oldVis);
    after = findall(groot, 'Type', 'figure');
    for k = 1:numel(after)
        if ~isvalid(after(k))
            continue;
        end
        if isempty(beforeFigs) || ~any(after(k) == beforeFigs)
            delete(after(k));
        end
    end
end
