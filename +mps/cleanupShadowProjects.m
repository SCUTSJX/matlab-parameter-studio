function removed = cleanupShadowProjects(maxAgeDays)
%CLEANUPSHADOWPROJECTS Remove stale temporary project shadows.
%
%   removed = mps.cleanupShadowProjects(7)
%
%   Only folders with the mps_shadow_ / mps_project_ prefix are considered,
%   and only when their timestamp is older than maxAgeDays.  Active shadows
%   are refreshed on every run and therefore stay below the age threshold.

    if nargin < 1 || isempty(maxAgeDays)
        maxAgeDays = 7;
    end
    removed = 0;
    patterns = {'mps_shadow_*', 'mps_project_*'};
    nowDate = now;
    for p = 1:numel(patterns)
        items = dir(fullfile(tempdir, patterns{p}));
        for k = 1:numel(items)
            item = items(k);
            if ~item.isdir || strcmp(item.name, '.') || strcmp(item.name, '..')
                continue;
            end
            stamp = item.datenum;
            marker = fullfile(item.folder, item.name, '.mps_touch');
            if isfile(marker)
                d = dir(marker);
                if ~isempty(d)
                    stamp = d(1).datenum;
                end
            end
            ageDays = nowDate - stamp;
            if ageDays < maxAgeDays
                continue;
            end
            try
                rmdir(fullfile(item.folder, item.name), 's');
                removed = removed + 1;
            catch err
                mps.logWarning(mps.tr('清理影子目录 %s', ...
                    'Clean shadow folder %s', item.name), err);
            end
        end
    end
end
