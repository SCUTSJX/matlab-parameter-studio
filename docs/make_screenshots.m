%MAKE_SCREENSHOTS Regenerate docs screenshots in Chinese and English.
%
%   Run in a desktop MATLAB session:
%       run('docs/make_screenshots.m')
%
%   Produces both language sets:
%       docs/screenshot.png / docs/screenshot_en.png
%       docs/screenshot_annotations.png / docs/screenshot_annotations_en.png
%       docs/screenshot_sweep.png / docs/screenshot_sweep_en.png
%
%   The path shown in the UI must not contain a real user home directory.
%   Override the demo location with MPS_SCREENSHOT_DEMO_DIR if needed.

root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
demoDir = getenv('MPS_SCREENSHOT_DEMO_DIR');
if isempty(demoDir)
    if ispc
        demoDir = fullfile(getenv('SystemDrive'), 'MATLAB', 'demo');
    else
        demoDir = fullfile(tempdir, 'mps-demo');
    end
end
if ~isfolder(demoDir)
    mkdir(demoDir);
end
demo = fullfile(demoDir, 'demo_simulation.m');
copyfile(fullfile(root, 'demo', 'demo_simulation.m'), demo);

oldLang = mps.language();
langCleaner = onCleanup(@() mps.setLanguage(oldLang)); %#ok<NASGU>

langs = {'zh', 'en'};
suffixes = {'', '_en'};
for li = 1:numel(langs)
    lang = langs{li};
    suffix = suffixes{li};
    mps.setLanguage(lang);
    cleanupRunOutputs(demoDir);

    app = mps.App('Visible', 'on');
    cleaner = onCleanup(@() delete(app));
    app.UIFigure.Position = [100 100 1330 840];
    app.loadFile(demo);
    app.setParam('m', 2);
    app.setParam('k', 8);
    app.setParam('c', 0.5);
    app.runCurrent();
    drawnow;
    exportapp(app.UIFigure, fullfile(root, 'docs', ...
        ['screenshot' suffix '.png']));

    ann = struct();
    ann.m = struct('description', 'mass', 'unit', 'kg');
    ann.k = struct('description', 'spring stiffness', 'unit', 'N/m');
    ann.c = struct('description', 'damping coefficient', 'unit', 'N*s/m');
    ann.x0 = struct('description', 'initial displacement', 'unit', 'm');
    ann.v0 = struct('description', 'initial velocity', 'unit', 'm/s');
    ann.tEnd = struct('description', 'simulation time', 'unit', 's');
    ann.dt = struct('description', 'output time step', 'unit', 's');
    annPath = fullfile(demoDir, 'demo_annotations.json');
    fid = fopen(annPath, 'w', 'n', 'UTF-8');
    fprintf(fid, '%s', jsonencode(ann));
    fclose(fid);
    app.importAnnotations(annPath);
    drawnow;
    exportapp(app.UIFigure, fullfile(root, 'docs', ...
        ['screenshot_annotations' suffix '.png']));

    p = mps.scan(demo);
    ki = find(strcmp({p.name}, 'k'), 1);
    runner = mps.SweepRunner(demo, p, ki, {[4 8]}, true, 't', {'y'}, false);
    runner.MaxScenarios = 2;
    out = runner.run();
    if isfield(out, 'overlayPath') && ~isempty(out.overlayPath) ...
            && isfile(out.overlayPath)
        copyfile(out.overlayPath, fullfile(root, 'docs', ...
            ['screenshot_sweep' suffix '.png']));
    end

    clear cleaner;   % delete the app before the next language
    cleanupRunOutputs(demoDir);
    fprintf('Screenshots updated (%s) in %s\n', lang, ...
        fullfile(root, 'docs'));
end

mps.setLanguage(oldLang);

% -------------------------------------------------------------------------
function cleanupRunOutputs(demoDir)
    runRoot = fullfile(demoDir, 'parameter_studio_runs');
    if isfolder(runRoot)
        rmdir(runRoot, 's');
    end
    sidecars = { ...
        fullfile(demoDir, 'demo_simulation_session.json'), ...
        fullfile(demoDir, 'demo_simulation_manual.json'), ...
        fullfile(demoDir, 'demo_simulation_annotations.json'), ...
        fullfile(demoDir, 'demo_annotations.json')};
    for k = 1:numel(sidecars)
        if isfile(sidecars{k})
            delete(sidecars{k});
        end
    end
end
