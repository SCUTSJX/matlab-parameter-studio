%MAKE_SCREENSHOTS Regenerate docs screenshots with a generic demo path.
%
%   Run in a desktop MATLAB session:
%       run('docs/make_screenshots.m')
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

app = mps.App('Visible', 'on');
cleaner = onCleanup(@() delete(app)); %#ok<NASGU>
app.UIFigure.Position = [100 100 1330 840];
app.loadFile(demo);
app.setParam('m', 2);
app.setParam('k', 8);
app.setParam('c', 0.5);
app.runCurrent();
drawnow;
exportapp(app.UIFigure, fullfile(root, 'docs', 'screenshot.png'));

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
exportapp(app.UIFigure, fullfile(root, 'docs', 'screenshot_annotations.png'));

runRoot = fullfile(demoDir, 'parameter_studio_runs');
if isfolder(runRoot)
    rmdir(runRoot, 's');
end
sidecars = {mps.sessionPath(demo), mps.manualParamsPath(demo), ...
    fullfile(demoDir, 'demo_simulation_annotations.json'), annPath};
for k = 1:numel(sidecars)
    if isfile(sidecars{k})
        delete(sidecars{k});
    end
end
fprintf('Screenshots updated in %s\n', fullfile(root, 'docs'));
