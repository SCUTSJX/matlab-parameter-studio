function p = presetsPath(sourceFile)
%PRESETSPATH Location of the parameter-preset JSON next to a script.
%
%   p = mps.presetsPath('demo_simulation.m')
%       -> '...\demo_simulation_presets.json'

    [folder, base] = fileparts(sourceFile);
    p = fullfile(folder, [base '_presets.json']);
end
