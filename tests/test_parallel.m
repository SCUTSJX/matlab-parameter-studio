% test_parallel tests. Executed in the run_tests workspace.

    % --- 21. SweepRunner -------------------------------------------------
    sweepDemo = fullfile(tempdir, 'mps_sweep_runner_demo.m');
    copyfile(demo, sweepDemo);
    pRun = mps.scan(sweepDemo);
    kiRun = find(strcmp({pRun.name}, 'k'), 1);
    runner = mps.SweepRunner(sweepDemo, pRun, kiRun, {[4 8]}, ...
        true, 't', {'y'}, false);
    runner.Progress = @(fraction, message) [];
    sweepOut = runner.run();
    assert(sweepOut.ok, 'SweepRunner failed');
    assert(sweepOut.count == 2, 'SweepRunner should run two scenarios');
    assert(isfile(sweepOut.report), 'SweepRunner report missing');
    assert(isfile(sweepOut.metricsPath), 'SweepRunner metrics CSV missing');
    assert(isfile(sweepOut.overlayPath), 'SweepRunner overlay missing');
    sweepRootOut = fullfile(fileparts(sweepDemo), 'parameter_studio_runs');
    if isfolder(sweepRootOut)
        rmdir(sweepRootOut, 's');
    end
    delete(sweepDemo);
    fprintf('  sweep runner: ok\n');

    if license('test', 'Distrib_Computing_Toolbox')
        parallelDemo = fullfile(tempdir, 'mps_sweep_parallel_demo.m');
        copyfile(demo, parallelDemo);
        pPar = mps.scan(parallelDemo);
        kiPar = find(strcmp({pPar.name}, 'k'), 1);
        runnerPar = mps.SweepRunner(parallelDemo, pPar, kiPar, ...
            {[4 8]}, true, 't', {'y'}, false);
        runnerPar.Parallel = true;
        runnerPar.Progress = @(fraction, message) [];
        parOut = runnerPar.run();
        assert(parOut.ok, 'parallel sweep failed');
        assert(parOut.count == 2, 'parallel sweep should run two scenarios');
        assert(isfile(parOut.report), 'parallel sweep report missing');
        assert(isfile(parOut.metricsPath), 'parallel sweep metrics missing');
        parRoot = fullfile(fileparts(parallelDemo), 'parameter_studio_runs');
        if isfolder(parRoot)
            rmdir(parRoot, 's');
        end
        delete(parallelDemo);

        bgDemo = fullfile(tempdir, 'mps_background_demo.m');
        copyfile(demo, bgDemo);
        pBg = mps.scan(bgDemo);
        pool = gcp('nocreate');
        future = parfeval(pool, @mps.backgroundRun, 1, ...
            bgDemo, pBg, 100, 512);
        bgOut = fetchOutputs(future);
        assert(bgOut.run.ok, 'backgroundRun failed');
        assert(isfile(bgOut.reportPath), 'background report missing');
        bgRoot = fullfile(fileparts(bgDemo), 'parameter_studio_runs');
        if isfolder(bgRoot)
            rmdir(bgRoot, 's');
        end
        delete(bgDemo);
        fprintf('  parallel sweep + background run: ok\n');
    end

    % --- 22. Interactive-call detection + sweep cancel -------------------
    interactiveFile = fullfile(tempdir, 'mps_interactive_test.m');
    fid = fopen(interactiveFile, 'w', 'n', 'UTF-8');
    fprintf(fid, ['%% input(''fake'');\n' ...
        's = ''input(''ignored'')'';\n' ...
        'answer = input(''value? '');\n' ...
        'pause(0.1);\n' ...
        'keyboard;\n']);
    fclose(fid);
    calls = mps.detectInteractiveCalls(interactiveFile);
    names = {calls.name};
    assert(any(strcmp(names, 'input')), 'input() should be detected');
    assert(any(strcmp(names, 'pause')), 'pause() should be detected');
    assert(any(strcmp(names, 'keyboard')), 'keyboard should be detected');
    assert(sum(strcmp(names, 'input')) == 1, ...
        'commented/string input calls should be ignored');
    delete(interactiveFile);

    sweepDemo2 = fullfile(tempdir, 'mps_sweep_cancel_demo.m');
    copyfile(demo, sweepDemo2);
    pCancel = mps.scan(sweepDemo2);
    kiCancel = find(strcmp({pCancel.name}, 'k'), 1);
    runnerCancel = mps.SweepRunner(sweepDemo2, pCancel, kiCancel, ...
        {[4 8]}, false, '', {}, false);
    runnerCancel.ShouldCancel = @() true;
    cancelOut = runnerCancel.run();
    assert(cancelOut.canceled, 'sweep runner should report cancellation');
    assert(cancelOut.count == 0, 'cancelled sweep should run no scenarios');
    cancelRoot = fullfile(fileparts(sweepDemo2), 'parameter_studio_runs');
    if isfolder(cancelRoot)
        rmdir(cancelRoot, 's');
    end
    delete(sweepDemo2);
    fprintf('  interactive detection + sweep cancel: ok\n');

    if ~hadPool
        try
            delete(gcp('nocreate'));
        catch
        end
    end
