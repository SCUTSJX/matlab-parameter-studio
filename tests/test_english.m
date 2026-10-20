% English UI smoke test. Executed in the run_tests workspace.

    previousLanguage = mps.language();
    languageCleanup = onCleanup(@() mps.setLanguage(previousLanguage)); %#ok<NASGU>
    mps.setLanguage('en');
    assert(strcmp(mps.language(), 'en'), 'language switch failed');
    assert(strcmp(mps.tr('中文', 'English'), 'English'), ...
        'mps.tr should return English text');

    englishDemo = fullfile(tempdir, 'mps_english_demo.m');
    copyfile(demo, englishDemo);
    appEnglish = mps.App('Visible', 'off');
    appEnglish.loadFile(englishDemo);
    assert(~isempty(appEnglish.Params), ...
        'English app should load the demo parameters');

    labels = get(findall(appEnglish.UIFigure, 'Type', 'uibutton'), 'Text');
    if ischar(labels)
        labels = {labels};
    end
    assert(any(cellfun(@(s) contains(char(s), 'Run'), labels)), ...
        'English UI should contain a Run button');

    appEnglish.setParam('k', 8);
    appEnglish.runCurrent();
    assert(~isempty(appEnglish.Results.LastReport), ...
        'English run should produce a report');
    reportText = fileread(appEnglish.Results.LastReport);
    assert(contains(reportText, 'Report') || ...
        contains(reportText, 'Parameter'), ...
        'English HTML report should use English headings');
    delete(appEnglish);

    if license('test', 'Distrib_Computing_Toolbox')
        pEnglish = mps.scan(englishDemo);
        kiEnglish = find(strcmp({pEnglish.name}, 'k'), 1);
        runnerEnglish = mps.SweepRunner(englishDemo, pEnglish, ...
            kiEnglish, {[4 8]}, false, '(None)', {'y'}, false);
        runnerEnglish.Parallel = true;
        runnerEnglish.NumWorkers = 2;
        runnerEnglish.MaxWorkers = 2;
        runnerEnglish.Progress = @(fraction, message) [];
        sweepEnglish = runnerEnglish.run();
        assert(sweepEnglish.ok && sweepEnglish.count == 2, ...
            'English parallel sweep should run two scenarios');
    end
    if ~hadPool
        try
            delete(gcp('nocreate'));
        catch
        end
    end

    englishRoot = fullfile(fileparts(englishDemo), 'parameter_studio_runs');
    if isfolder(englishRoot)
        rmdir(englishRoot, 's');
    end
    if isfile(mps.sessionPath(englishDemo))
        delete(mps.sessionPath(englishDemo));
    end
    delete(englishDemo);
    mps.setLanguage(previousLanguage);
    clear languageCleanup;
    fprintf('  English UI smoke test: ok\n');
