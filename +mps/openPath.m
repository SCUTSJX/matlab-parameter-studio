function openPath(target)
%OPENPATH Open a file or folder with the operating system's default tool.
%
%   mps.openPath(path) works on Windows, macOS and Linux.  The app uses it
%   for the result folder button; the run history dialog uses it for both
%   folders and reports.

    target = char(target);
    if ~isfile(target) && ~isfolder(target)
        error('mps:openPath:notFound', '路径不存在：%s', target);
    end

    if ispc
        winopen(target);
    elseif ismac
        system(['open "' target '"']);
    else
        system(['xdg-open "' target '" &']);
    end
end
