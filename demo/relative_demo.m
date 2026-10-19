% Demo: a script that loads a data file relative to its own folder.
% This checks that the generated script runs with the original folder as
% the current folder.
clear; close all; clc;

gain = 2;          % gain applied to the loaded signal
data = load('demo_data.mat');
x = data.x;
y = gain * x;

figure('Name', 'Relative path demo');
plot(x, y, 'LineWidth', 1.5);
grid on;
xlabel('x');
ylabel('gain * x');

fprintf('loaded %d points, gain = %.2f\n', numel(x), gain);
