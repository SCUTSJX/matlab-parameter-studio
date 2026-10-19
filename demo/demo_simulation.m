% Demo: damped spring-mass system.
% This file is intentionally simple.  The Parameter Studio should detect
% m, k, c, x0, v0, tEnd and dt as recommended parameters.
clear; close all; clc;

m = 1.0;          % mass [kg]
k = 4.0;          % spring stiffness [N/m]
c = 0.2;          % damping coefficient [N*s/m]
x0 = 1.0;         % initial displacement [m]
v0 = 0.0;         % initial velocity [m/s]
tEnd = 10;        % simulation time [s]
dt = 0.01;        % output time step [s]

A = [0 1; -k/m -c/m];
B = [0; 1/m];
f = @(t, x) A*x + B*0;
[t, x] = ode45(f, 0:dt:tEnd, [x0; v0]);
y = x(:, 1);

figure('Name', 'Displacement');
plot(t, y, 'LineWidth', 1.5);
grid on;
xlabel('Time (s)');
ylabel('Displacement (m)');
title(sprintf('m=%.2f, k=%.2f, c=%.2f', m, k, c));

figure('Name', 'Phase portrait');
plot(x(:,1), x(:,2));
grid on;
xlabel('x (m)');
ylabel('v (m/s)');

fprintf('Peak displacement: %.4f m\n', max(abs(y)));
