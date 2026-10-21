% Annotation demo: % @param and % @ignore markers.
% Generate/import annotations from the app to fill in descriptions and units.

clear; close all; clc;

gain = 2.0;       % @param controller gain
damping = 0.2;    % damping ratio
frequency = 3.0;  % frequency [Hz]
tEnd = 8;         % simulation time [s]
dt = 0.01;        % time step [s]
lineWidth = 1.5;  % @ignore line width, not a physical parameter

t = 0:dt:tEnd;
y = gain * exp(-damping * t) .* sin(2*pi*frequency*t);

figure('Name', 'Annotated demo');
plot(t, y, 'LineWidth', lineWidth);
grid on;
xlabel('Time (s)');
ylabel('Response');
title(sprintf('gain=%.2f, damping=%.2f, frequency=%.2f Hz', ...
    gain, damping, frequency));
