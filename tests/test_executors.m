% test_executors tests. Executed in the run_tests workspace.

    % --- 20. RunExecutor -------------------------------------------------
    execDemo = fullfile(tempdir, 'mps_executor_demo.m');
    copyfile(demo, execDemo);
    pExec = mps.scan(execDemo);
    for k = 1:numel(pExec)
        if strcmp(pExec(k).name, 'k')
            pExec(k).newValue = '8';
            pExec(k).use = true;
        end
    end
    ex = mps.RunExecutor(execDemo, pExec, false);
    ex.Progress = @(msg) [];
    execOut = ex.run();
    assert(execOut.run.ok, 'RunExecutor run failed');
    assert(abs(execOut.run.workspaceData.k - 8) < 1e-12, ...
        'RunExecutor should apply k=8');
    assert(isfile(execOut.reportPath), 'RunExecutor report missing');
    execRoot = fullfile(fileparts(execDemo), 'parameter_studio_runs');
    if isfolder(execRoot)
        rmdir(execRoot, 's');
    end
    delete(execDemo);
    fprintf('  run executor: ok\n');
