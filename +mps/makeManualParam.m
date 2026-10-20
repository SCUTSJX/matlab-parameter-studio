function p = makeManualParam(sourceFile, name, value, description, unit)
%MAKEMANUALPARAM Build a parameter entered by the user.
%
%   Manual parameters are prepended as assignments by mps.applyEdits.  They
%   are persisted in <source>_manual.json so they survive re-scanning.

    if nargin < 4, description = ''; end
    if nargin < 5, unit = ''; end
    name = strtrim(char(name));
    value = strtrim(char(value));
    if ~isvarname(name)
        error('mps:makeManualParam:badName', ...
            '参数名必须是合法 MATLAB 变量名：%s', name);
    end
    [ok, ~] = mps.validateValue(value);
    if ~ok || isempty(value)
        error('mps:makeManualParam:badValue', ...
            '手动参数的值无效：%s', value);
    end
    p = struct();
    p.id = sprintf('manual|%s', name);
    p.name = name;
    p.value = value;
    p.newValue = value;
    p.line = 0;
    p.colStart = 0;
    p.colEnd = 0;
    p.score = 10;
    p.category = 'manual';
    p.note = '手动添加';
    p.context = '';
    p.use = true;
    p.isChanged = false;
    p.sourceFile = char(sourceFile);
    p.literalIndex = 0;
    p.isLogical = false;
    p.description = char(description);
    p.unit = char(unit);
    p.locked = false;
    p.ignored = false;
    p.manual = true;
end
