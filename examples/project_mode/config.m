function cfg = config()
%CONFIG Configuration values for the project-mode example.
%
%   Open this file in MATLAB Parameter Studio, choose entry.m as the project
%   entry point, and tune cfg.gain / cfg.damping / cfg.frequency.

    cfg = struct();
    cfg.gain = 2.0;       % @param controller gain
    cfg.damping = 0.2;    % damping ratio
    cfg.frequency = 3.0;  % frequency [Hz]
    cfg.tEnd = 8;         % simulation time [s]
end
