function openPath(target)
%OPENPATH Open a file or folder with the operating system's default tool.
%
%   mps.openPath(path) works on Windows, macOS and Linux.  The app uses it
%   for the result folder button; the run history dialog uses it for both
%   folders and reports.

    target = char(target);
    if ~isfile(target) && ~isfolder(target)
        error('mps:openPath:notFound', ...
            mps.tr('路径不存在：%s', 'Path does not exist: %s'), target);
    end

    if ispc
        winopen(target);
    else
        % POSIX shell: wrap the path in single quotes and turn embedded
        % quotes into '"'"' so paths with quotes, spaces or $ cannot break
        % out of the command.
        q = '''';                    % single quote character
        esc = [q '\' q q];           % '\''
        quoted = ['''' strrep(target, q, esc) ''''];
        if ismac
            system(['open ' quoted]);
        else
            system(['xdg-open ' quoted ' &']);
        end
    end
end
