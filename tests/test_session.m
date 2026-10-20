% test_session tests. Executed in the run_tests workspace.

    % --- 18. Undo / redo + session restore -------------------------------
    sessionDemo = fullfile(tempdir, 'mps_session_demo.m');
    copyfile(demo, sessionDemo);
    sessionFile = mps.sessionPath(sessionDemo);
    if isfile(sessionFile)
        delete(sessionFile);
    end
    appS = mps.App('Visible', 'off');
    appS.loadFile(sessionDemo);
    ki = find(strcmp({appS.Params.name}, 'k'), 1);
    kOriginal = appS.Params(ki).value;
    appS.setParam('k', 8);
    ki = find(strcmp({appS.Params.name}, 'k'), 1);
    assert(strcmp(appS.Params(ki).newValue, '8'), ...
        'setParam should update k');
    assert(isfile(sessionFile), 'session file should be written after edits');
    appS.undoLastEdit();
    ki = find(strcmp({appS.Params.name}, 'k'), 1);
    assert(strcmp(appS.Params(ki).newValue, kOriginal), ...
        'undo should restore the original k');
    appS.redoLastEdit();
    ki = find(strcmp({appS.Params.name}, 'k'), 1);
    assert(strcmp(appS.Params(ki).newValue, '8'), ...
        'redo should reapply k=8');
    delete(appS);

    appS2 = mps.App('Visible', 'off');
    appS2.loadFile(sessionDemo);
    ki = find(strcmp({appS2.Params.name}, 'k'), 1);
    assert(strcmp(appS2.Params(ki).newValue, '8'), ...
        'session should restore the unsaved k value');
    delete(appS2);
    if isfile(sessionFile)
        delete(sessionFile);
    end
    delete(sessionDemo);
    fprintf('  undo/redo + session: ok\n');

    % --- 19. Diff preview + source stamp ---------------------------------
    stamp1 = mps.sourceStamp(demo);
    diffText = mps.textDiff( ...
        sprintf('a = 1;\nb = 2;\n'), sprintf('a = 3;\nb = 2;\n'));
    assert(any(strncmp(diffText, '- ', 2)), 'diff should contain a removed line');
    assert(any(strncmp(diffText, '+ ', 2)), 'diff should contain an added line');
    dlgDiff = mps.DiffDialog('test', diffText, 'Visible', 'off');
    dlgDiff.confirm();
    assert(dlgDiff.Result, 'diff dialog confirm should set Result');
    delete(dlgDiff);
    dlgDiff2 = mps.DiffDialog('test', diffText, 'Visible', 'off');
    dlgDiff2.cancel();
    assert(~dlgDiff2.Result, 'diff dialog cancel should clear Result');
    delete(dlgDiff2);

    stampFile = fullfile(tempdir, 'mps_stamp_test.m');
    fid = fopen(stampFile, 'w', 'n', 'UTF-8');
    fprintf(fid, 'a = 1;\n');
    fclose(fid);
    stamp2 = mps.sourceStamp(stampFile);
    fid = fopen(stampFile, 'w', 'n', 'UTF-8');
    fprintf(fid, 'a = 2;\n');
    fclose(fid);
    stamp3 = mps.sourceStamp(stampFile);
    assert(~mps.sameSourceStamp(stamp2, stamp3), ...
        'source stamp should detect a changed file');
    assert(mps.sameSourceStamp(stamp1, mps.sourceStamp(demo)), ...
        'source stamp should be stable for an unchanged file');
    delete(stampFile);
    fprintf('  diff preview + source stamp: ok\n');
