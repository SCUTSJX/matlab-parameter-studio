% test_project tests. Executed in the run_tests workspace.

    % --- 20b. Project entry execution -----------------------------------
    projectRoot = fullfile(tempdir, 'mps_project_runner_test');
    if isfolder(projectRoot)
        rmdir(projectRoot, 's');
    end
    mkdir(projectRoot);
    fid = fopen(fullfile(projectRoot, 'config.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, 'function c=config()\nc.gain=1;\nc.bias=2;\nend\n');
    fclose(fid);
    fid = fopen(fullfile(projectRoot, 'entry.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, ['c=config(); y=c.gain*10; ' ...
        'figure(''Name'',''project''); plot(1:3);\n']);
    fclose(fid);
    pProj = mps.scan(fullfile(projectRoot, 'config.m'));
    gi = find(strcmp({pProj.name}, 'c.gain'), 1);
    pProj(gi).newValue = '5';
    pProj(gi).use = true;
    projExec = mps.ProjectRunExecutor( ...
        fullfile(projectRoot, 'config.m'), ...
        fullfile(projectRoot, 'entry.m'), pProj, false);
    projExec.Progress = @(msg) [];
    projOut = projExec.run();
    assert(projOut.run.ok, 'ProjectRunExecutor failed');
    assert(abs(projOut.run.workspaceData.y - 50) < 1e-12, ...
        'project entry should use the tuned config');
    assert(isfile(projOut.reportPath), 'project report missing');
    rmdir(projectRoot, 's');

    multiRoot = fullfile(tempdir, 'mps_multi_project_test');
    if isfolder(multiRoot)
        rmdir(multiRoot, 's');
    end
    mkdir(multiRoot);
    fid = fopen(fullfile(multiRoot, 'config.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, 'function c=config()\nc.gain=1;\nend\n');
    fclose(fid);
    fid = fopen(fullfile(multiRoot, 'helper.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, 'function h=helper()\nh.bias=2;\nend\n');
    fclose(fid);
    fid = fopen(fullfile(multiRoot, 'entry.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, ['c=config(); h=helper(); y=c.gain*10+h.bias; ' ...
        'figure(''Name'',''multi''); plot(1:3);\n']);
    fclose(fid);
    pMulti = mps.scanProject(multiRoot);
    gi = find(strcmp({pMulti.name}, 'c.gain'), 1);
    bi = find(strcmp({pMulti.name}, 'h.bias'), 1);
    pMulti(gi).newValue = '5';
    pMulti(gi).use = true;
    pMulti(bi).newValue = '7';
    pMulti(bi).use = true;
    multiExec = mps.ProjectRunExecutor( ...
        fullfile(multiRoot, 'entry.m'), fullfile(multiRoot, 'entry.m'), ...
        pMulti, false);
    multiExec.Progress = @(msg) [];
    multiOut = multiExec.run();
    assert(multiOut.run.ok, 'multi-file project run failed');
    assert(abs(multiOut.run.workspaceData.y - 57) < 1e-12, ...
        'multi-file project edits were not both applied');
    pMulti2 = pMulti;
    gi = find(strcmp({pMulti2.name}, 'c.gain'), 1);
    bi = find(strcmp({pMulti2.name}, 'h.bias'), 1);
    pMulti2(gi).newValue = '3';
    pMulti2(bi).newValue = '9';
    multiExec2 = mps.ProjectRunExecutor( ...
        fullfile(multiRoot, 'entry.m'), fullfile(multiRoot, 'entry.m'), ...
        pMulti2, false);
    multiExec2.Progress = @(msg) [];
    multiOut2 = multiExec2.run();
    assert(abs(multiOut2.run.workspaceData.y - 39) < 1e-12, ...
        'reused project shadow must receive fresh edits');
    rmdir(multiRoot, 's');

    sweepProject = fullfile(tempdir, 'mps_project_sweep_test');
    if isfolder(sweepProject)
        rmdir(sweepProject, 's');
    end
    mkdir(sweepProject);
    fid = fopen(fullfile(sweepProject, 'config.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, 'function c=config()\nc.gain=1;\nend\n');
    fclose(fid);
    fid = fopen(fullfile(sweepProject, 'entry.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, 'c=config(); y=c.gain*10;\n');
    fclose(fid);
    pSweepProject = mps.scanProject(sweepProject);
    gs = find(strcmp({pSweepProject.name}, 'c.gain'), 1);
    projectSweep = mps.SweepRunner( ...
        fullfile(sweepProject, 'entry.m'), pSweepProject, gs, ...
        {[1 2]}, false, '', {}, false);
    projectSweep.ProjectMode = true;
    projectSweep.EntryFile = fullfile(sweepProject, 'entry.m');
    projectSweep.Progress = @(fraction, message) [];
    projectSweepOut = projectSweep.run();
    assert(projectSweepOut.count == 2, ...
        'project sweep should run two scenarios');
    assert(isfile(projectSweepOut.report), ...
        'project sweep report missing');
    rmdir(sweepProject, 's');
    fprintf('  project entry execution: ok\n');
