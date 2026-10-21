% Project-mode example: config.m supplies the parameters, this script runs.
% In MATLAB Parameter Studio, open config.m, choose this file as the entry
% point, and click Run. The app runs a temporary shadow copy of the project.

clear; close all; clc;

cfg = config();
t = 0:0.01:cfg.tEnd;
y = cfg.gain * exp(-cfg.damping * t) .* sin(2*pi*cfg.frequency*t);

figure('Name', 'Project mode demo');
plot(t, y, 'LineWidth', 1.5);
grid on;
xlabel('Time (s)');
ylabel('Response');
title(sprintf('gain=%.2f, damping=%.2f, frequency=%.2f Hz', ...
    cfg.gain, cfg.damping, cfg.frequency));
