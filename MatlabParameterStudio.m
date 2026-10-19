function app = MatlabParameterStudio(varargin)
%MATLABPARAMETERSTUDIO Launch the MATLAB Parameter Studio app.
%
%   Usage:
%       MatlabParameterStudio
%       MatlabParameterStudio('Visible', 'off')   % automation / tests
%
%   The app scans a .m script for editable numeric values, lets you change
%   them, runs the script, captures figures/workspace variables, and writes
%   an HTML report.  It also saves a tuned copy of the script that can be run
%   directly in MATLAB without this app.
%
%   See README.md for details and limitations.

    root = fileparts(mfilename('fullpath'));
    addpath(root);
    app = mps.App(varargin{:});
    if nargout == 0
        % The app keeps itself alive through UIFigure.UserData.  Drop the
        % local reference so the command line stays clean.
        clear app;
    end
end
