% Sweep demo: damped spring-mass response.
% Open this file in MATLAB Parameter Studio, then use Batch sweep on k/c.

clear; close all; clc;

m = 1;          % mass [kg]
k = 4;          % spring stiffness [N/m]
c = 0.3;        % damping coefficient [N*s/m]
x0 = 1;         % initial displacement [m]
v0 = 0;         % initial velocity [m/s]
tEnd = 10;      % simulation time [s]
dt = 0.01;      % output time step [s]

A = [0 1; -k/m -c/m];
f = @(t, x) A*x;
[t, x] = ode45(f, 0:dt:tEnd, [x0; v0]);
y = x(:, 1);

figure('Name', 'Sweep demo');
plot(t, y, 'LineWidth', 1.5);
grid on;
xlabel('Time (s)');
ylabel('Displacement (m)');
title(sprintf('k=%.2f, c=%.2f', k, c));
