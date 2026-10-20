function out = tr(zh, en, varargin)
%TR Return user-visible text in the current UI language.
%
%   mps.tr('打开文件', 'Open file')
%   mps.tr('已处理 %d 个参数', 'Processed %d parameters', n)
%
%   zh/en may be character vectors or scalar strings.  Additional arguments
%   are passed through sprintf after selecting the language.  When English
%   text is not supplied, the Chinese text is returned unchanged.

    if nargin < 2 || isempty(en)
        en = zh;
    end
    if strcmp(mps.language(), 'en')
        out = char(en);
    else
        out = char(zh);
    end
    if nargin > 2
        out = sprintf(out, varargin{:});
    end
end
