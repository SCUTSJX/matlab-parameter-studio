% Cleanup and shadow-sync tests. Executed in the run_tests workspace.

    shadowSource = fullfile(tempdir, 'mps_shadow_sync_source');
    if isfolder(shadowSource)
        rmdir(shadowSource, 's');
    end
    mkdir(shadowSource);
    fid = fopen(fullfile(shadowSource, 'keep.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, 'a = 1;\n');
    fclose(fid);
    fid = fopen(fullfile(shadowSource, 'remove.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, 'b = 2;\n');
    fclose(fid);
    sid = fopen(fullfile(shadowSource, 'input.txt'), 'w', 'n', 'UTF-8');
    fprintf(sid, 'input\n');
    fclose(sid);

    shadowA = mps.prepareShadowProject(shadowSource);
    assert(isfile(fullfile(shadowA, 'remove.m')), ...
        'shadow should contain the first snapshot');
    delete(fullfile(shadowSource, 'remove.m'));
    fid = fopen(fullfile(shadowSource, 'added.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, 'c = 3;\n');
    fclose(fid);
    shadowB = mps.prepareShadowProject(shadowSource);
    assert(strcmp(shadowA, shadowB), 'shadow path should be reused');
    assert(~isfile(fullfile(shadowB, 'remove.m')), ...
        'deleted source file should be removed from the shadow');
    assert(isfile(fullfile(shadowB, 'added.m')), ...
        'new source file should be copied into the shadow');

    stale = fullfile(tempdir, 'mps_shadow_cleanup_test');
    if isfolder(stale)
        rmdir(stale, 's');
    end
    mkdir(stale);
    marker = fullfile(stale, '.mps_touch');
    fid = fopen(marker, 'w');
    fprintf(fid, 'stale\n');
    fclose(fid);
    removed = mps.cleanupShadowProjects(0);
    assert(removed >= 1, 'cleanup should remove at least the stale shadow');
    assert(~isfolder(stale), 'stale shadow folder should be gone');
    if isfolder(shadowSource)
        rmdir(shadowSource, 's');
    end
    mps.logWarning('测试日志', 'expected warning', 'Silent', true);
    assert(isfile(fullfile(tempdir, 'matlab_parameter_studio.log')), ...
        'logWarning should write a log file');
    preflightDir = fullfile(tempdir, 'mps_preflight_test');
    if isfolder(preflightDir)
        rmdir(preflightDir, 's');
    end
    mkdir(preflightDir);
    for oldLog = 1:3
        oldName = sprintf('preflight_2020010%d_000000.log', oldLog);
        fid = fopen(fullfile(preflightDir, oldName), 'w', 'n', 'UTF-8');
        fprintf(fid, 'old log %d\n', oldLog);
        fclose(fid);
    end
    pre = mps.preflight('Full', false, 'LogDir', preflightDir, ...
        'KeepLogs', 2);
    assert(pre.ok, pre.error);
    assert(isfile(pre.logFile), 'preflight should write a timestamped log');
    kept = dir(fullfile(preflightDir, 'preflight_*.log'));
    assert(numel(kept) == 2, 'KeepLogs should keep only the newest logs');

    fid = fopen(pre.logFile, 'r');
    logBytes = fread(fid, Inf, '*uint8')';
    fclose(fid);
    logText = char(logBytes);
    assert(isempty(strfind(logText, root)), ...
        'preflight log should not contain the absolute repo path');
    userProfile = getenv('USERPROFILE');
    if ~isempty(userProfile)
        assert(isempty(strfind(logText, userProfile)), ...
            'preflight log should not contain the local user profile');
    end
    if isfolder(preflightDir)
        rmdir(preflightDir, 's');
    end
    fprintf('  shadow sync + cleanup: ok\n');
