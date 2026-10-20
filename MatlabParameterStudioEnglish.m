function app = MatlabParameterStudioEnglish(varargin)
%MATLABPARAMETERSTUDIOENGLISH Launch MATLAB Parameter Studio with the English UI.
%
%   MatlabParameterStudioEnglish
%   MatlabParameterStudioEnglish('Visible', 'off')
%
%   The Chinese UI remains available through MatlabParameterStudio.

    root = fileparts(mfilename('fullpath'));
    addpath(root);
    mps.setLanguage('en');
    app = mps.App(varargin{:});
    if nargout == 0
        clear app;
    end
end
