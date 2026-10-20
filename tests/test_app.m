% test_app tests. Executed in the run_tests workspace.

    % --- 23. App UI construction -----------------------------------------
    app = mps.App('Visible', 'off');
    app.loadFile(demo);
    assert(~isempty(app.Params), 'app should load the demo parameters');
    ki = find(strcmp({app.Params.name}, 'k'), 1);
    app.toggleLock('k');
    assert(app.Params(ki).locked, 'public toggleLock should lock k');
    app.toggleLock('k');
    assert(~app.Params(ki).locked, 'public toggleLock should unlock k');
    app.Params(1).description = '测试注释';
    app.clearAnnotations();
    assert(isempty(app.Params(1).description), ...
        'clearAnnotations should clear descriptions');

    manualLoad = fullfile(tempdir, 'mps_manual_load.m');
    copyfile(demo, manualLoad);
    pLoad = mps.scan(manualLoad);
    pLoad = [pLoad, mps.makeManualParam(manualLoad, 'gain', '3')];
    mps.writeManualParams(manualLoad, pLoad);
    app.loadFile(manualLoad);
    assert(any(strcmp({app.Params.name}, 'gain')), ...
        'loadFile should restore manual parameters');

    uiProject = fullfile(tempdir, 'mps_ui_project_test');
    if isfolder(uiProject)
        rmdir(uiProject, 's');
    end
    mkdir(uiProject);
    fid = fopen(fullfile(uiProject, 'config.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, 'function c=config()\nc.gain=1;\nend\n');
    fclose(fid);
    fid = fopen(fullfile(uiProject, 'entry.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, 'c=config(); y=c.gain*2;\n');
    fclose(fid);
    app.loadFile(fullfile(uiProject, 'config.m'));
    app.setEntryPoint(fullfile(uiProject, 'entry.m'));
    app.runCurrent();
    assert(~isempty(app.Results.LastReport), ...
        'project entry run should create a report');
    rmdir(uiProject, 's');

    uiMulti = fullfile(tempdir, 'mps_ui_multi_project_test');
    if isfolder(uiMulti)
        rmdir(uiMulti, 's');
    end
    mkdir(uiMulti);
    fid = fopen(fullfile(uiMulti, 'config.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, 'function c=config()\nc.gain=1;\nend\n');
    fclose(fid);
    fid = fopen(fullfile(uiMulti, 'helper.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, 'function h=helper()\nh.bias=2;\nend\n');
    fclose(fid);
    fid = fopen(fullfile(uiMulti, 'entry.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, ['c=config(); h=helper(); y=c.gain*10+h.bias;\n']);
    fclose(fid);
    app.loadProject(fullfile(uiMulti, 'entry.m'));
    assert(app.ProjectMode, 'loadProject should enable project mode');
    assert(numel(unique({app.Params.sourceFile})) >= 2, ...
        'project scan should cover multiple files');
    app.runCurrent();
    assert(~isempty(app.Results.LastReport), ...
        'multi-file project run should create a report');
    rmdir(uiMulti, 's');
    delete(app);
    if isfile(mps.sessionPath(manualLoad))
        delete(mps.sessionPath(manualLoad));
    end
    if isfile(mps.manualParamsPath(manualLoad))
        delete(mps.manualParamsPath(manualLoad));
    end
    delete(manualLoad);
    if isfile(mps.sessionPath(demo))
        delete(mps.sessionPath(demo));
    end

    if license('test', 'Distrib_Computing_Toolbox')
        bgAppDemo = fullfile(tempdir, 'mps_app_background_demo.m');
        copyfile(demo, bgAppDemo);
        appBg = mps.App('Visible', 'off');
        appBg.loadFile(bgAppDemo);
        boxes = findall(appBg.UIFigure, 'Type', 'uicheckbox');
        for k = 1:numel(boxes)
            if strcmp(boxes(k).Text, '后台运行')
                boxes(k).Value = true;
            end
        end
        appBg.setParam('k', 8);
        appBg.runCurrent();
        deadline = tic;
        while isempty(appBg.Results.LastReport) && toc(deadline) < 120
            drawnow;
            pause(0.2);
        end
        assert(~isempty(appBg.Results.LastReport), ...
            'app background run should produce a report');
        assert(appBg.Results.LastRun.ok, appBg.Results.LastRun.error);
        assert(abs(appBg.Results.LastRun.workspaceData.k - 8) < 1e-12, ...
            'app background run should use the edited parameter');
        delete(appBg);
        bgRoot = fullfile(fileparts(bgAppDemo), 'parameter_studio_runs');
        if isfolder(bgRoot)
            rmdir(bgRoot, 's');
        end
        if isfile(mps.sessionPath(bgAppDemo))
            delete(mps.sessionPath(bgAppDemo));
        end
        if isfile(mps.manualParamsPath(bgAppDemo))
            delete(mps.manualParamsPath(bgAppDemo));
        end
        delete(bgAppDemo);
        if ~hadPool
            try
                delete(gcp('nocreate'));
            catch
            end
        end
    end
    fprintf('  app UI: ok\n');
