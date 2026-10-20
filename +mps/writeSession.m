function writeSession(sourceFile, params, stamp)
%WRITESESSION Save the current table state for crash/restart recovery.
%
%   mps.writeSession(sourceFile, params, stamp)
%
%   The file lives next to the script as <name>_session.json and is ignored
%   by git (see .gitignore).  It stores use / newValue / locked plus the
%   annotations already present on the parameters.

    if isempty(sourceFile) || isempty(params)
        return;
    end
    if nargin < 3 || isempty(stamp)
        stamp = mps.sourceStamp(sourceFile);
    end
    data = struct();
    data.sourceFile = char(sourceFile);
    data.savedAt = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    data.stamp = stamp;
    data.values = mps.paramsToValues(params);

    target = mps.sessionPath(sourceFile);
    fid = fopen(target, 'w', 'n', 'UTF-8');
    if fid < 0
        error('mps:writeSession:cannotWrite', ...
            mps.tr('无法写入会话文件：%s', ...
            'Cannot write session file: %s'), target);
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s', jsonencode(data));
    clear cleaner;
end
