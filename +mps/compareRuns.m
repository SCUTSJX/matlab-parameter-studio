function reportPath = compareRuns(dirA, dirB, outPath)
%COMPARERUNS Compare two run folders and write compare.html + compare.json.
%
%   reportPath = mps.compareRuns(dirA, dirB)
%   reportPath = mps.compareRuns(dirA, dirB, outPath)
%
%   dirA and dirB are run folders produced by the app.  Each folder may
%   contain parameters.json, workspace.mat and a figures/ subfolder.
%
%   The report lists:
%     - parameters whose effective run value differs,
%     - workspace variables compared numerically (max abs / RMS / relative),
%     - figures from both runs side by side.
%
%   Run it directly from MATLAB, for example:
%       mps.compareRuns('parameter_studio_runs/20261019_170000', ...
%                       'parameter_studio_runs/20261019_171500')

    if nargin < 3 || isempty(outPath)
        outPath = fullfile(dirB, 'compare.html');
    end
    if ~isfolder(dirA) || ~isfolder(dirB)
        error('mps:compareRuns:missingFolder', mps.tr( ...
            '运行目录不存在：%s / %s', 'Run folder not found: %s / %s'), ...
            dirA, dirB);
    end
    outDir = fileparts(outPath);
    if ~isempty(outDir) && ~isfolder(outDir)
        mkdir(outDir);
    end
    assetDir = fullfile(outDir, 'compare_assets');
    if ~isfolder(assetDir)
        mkdir(assetDir);
    end

    pA = loadParams(dirA);
    pB = loadParams(dirB);
    wsA = loadWorkspace(dirA);
    wsB = loadWorkspace(dirB);
    figA = listFigures(dirA);
    figB = listFigures(dirB);

    % --- Parameter comparison -------------------------------------------
    % Match by name + line, not name alone: a script may contain two
    % parameters with the same name on different lines.
    keysA = parameterKeys(pA);
    keysB = parameterKeys(pB);
    allKeys = unique([keysA, keysB], 'stable');
    paramDiffs = struct('name', {}, 'lineA', {}, 'lineB', {}, ...
        'valueA', {}, 'valueB', {}, 'changed', {}, 'only', {});
    nChanged = 0;
    for k = 1:numel(allKeys)
        key = allKeys{k};
        ia = find(strcmp(keysA, key), 1);
        ib = find(strcmp(keysB, key), 1);
        name = '';
        lineA = NaN;
        lineB = NaN;
        vA = '';
        vB = '';
        only = '';
        if ~isempty(ia)
            name = pA(ia).name;
            lineA = pA(ia).line;
            vA = effectiveValue(pA(ia));
        end
        if ~isempty(ib)
            if isempty(name)
                name = pB(ib).name;
            end
            lineB = pB(ib).line;
            vB = effectiveValue(pB(ib));
        end
        if isempty(ia)
            only = 'B';
        elseif isempty(ib)
            only = 'A';
        end
        changed = ~strcmp(vA, vB);
        if changed, nChanged = nChanged + 1; end
        paramDiffs(end+1) = struct('name', name, 'lineA', lineA, ...
            'lineB', lineB, 'valueA', vA, 'valueB', vB, ...
            'changed', changed, 'only', only); %#ok<AGROW>
    end

    % --- Workspace comparison -------------------------------------------
    fA = fieldnames(wsA);
    fB = fieldnames(wsB);
    common = intersect(fA, fB, 'stable');
    onlyA = setdiff(fA, fB, 'stable');
    onlyB = setdiff(fB, fA, 'stable');
    wsDiffs = struct('name', {}, 'classA', {}, 'classB', {}, ...
        'sizeA', {}, 'sizeB', {}, 'status', {}, 'maxAbs', {}, ...
        'rms', {}, 'rel', {});
    nDiffVars = 0;
    for k = 1:numel(common)
        name = common{k};
        A = wsA.(name);
        B = wsB.(name);
        szA = sizeString(size(A));
        szB = sizeString(size(B));
        clsA = class(A);
        clsB = class(B);
        status = '';
        maxAbs = NaN; rms = NaN; rel = NaN;
        numericA = isnumeric(A) || islogical(A);
        numericB = isnumeric(B) || islogical(B);
        if numericA && numericB && isequal(size(A), size(B))
            d = double(A(:)) - double(B(:));
            if isempty(d)
                maxAbs = 0; rms = 0; rel = 0;
            else
                ad = abs(d);
                maxAbs = max(ad);
                rms = sqrt(mean(ad.^2));
                ref = max(abs(double(A(:))));
                if ref == 0
                    ref = max(abs(double(B(:))));
                end
                rel = maxAbs / max(ref, 1e-12);
            end
            if maxAbs == 0
                status = mps.tr('相同', 'Same');
            else
                status = mps.tr('有差异', 'Different');
                nDiffVars = nDiffVars + 1;
            end
        else
            if ~strcmp(clsA, clsB) || ~isequal(size(A), size(B))
                status = mps.tr('类型/大小不同', 'Type/size differs');
            else
                status = mps.tr('非数值变量', 'Non-numeric variable');
            end
        end
        wsDiffs(end+1) = struct('name', name, 'classA', clsA, ...
            'classB', clsB, 'sizeA', szA, 'sizeB', szB, ...
            'status', status, 'maxAbs', maxAbs, 'rms', rms, 'rel', rel); %#ok<AGROW>
    end

    % --- Copy figures for a portable report -----------------------------
    assetsA = copyFigureSet(figA, assetDir, 'a');
    assetsB = copyFigureSet(figB, assetDir, 'b');

    % --- HTML -----------------------------------------------------------
    reportPath = outPath;
    fid = fopen(reportPath, 'w', 'n', 'UTF-8');
    if fid < 0
        error('mps:compareRuns:cannotWrite', mps.tr( ...
            '无法写入：%s', 'Cannot write: %s'), reportPath);
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

    stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    out = {};
    out{end+1} = '<!DOCTYPE html>';
    out{end+1} = mps.tr( ...
        '<html lang="zh-CN"><head><meta charset="utf-8">', ...
        '<html lang="en"><head><meta charset="utf-8">');
    out{end+1} = '<meta name="viewport" content="width=device-width, initial-scale=1">';
    out{end+1} = mps.tr('<title>运行对比报告</title>', ...
        '<title>Run comparison report</title>');
    out{end+1} = '<style>';
    out{end+1} = 'body{font-family:"Microsoft YaHei","Segoe UI",Arial,sans-serif;margin:0;background:#f5f7fb;color:#172033;line-height:1.55;}';
    out{end+1} = '.wrap{max-width:1200px;margin:0 auto;padding:32px 24px 60px;}';
    out{end+1} = 'h1{font-size:28px;margin:0 0 6px;}h2{font-size:19px;margin:30px 0 12px;border-left:4px solid #3b82f6;padding-left:10px;}';
    out{end+1} = '.sub{color:#667085;margin-bottom:24px;word-break:break-all;}';
    out{end+1} = '.cards{display:flex;gap:14px;flex-wrap:wrap;margin:22px 0 6px;}';
    out{end+1} = '.card{background:#fff;border:1px solid #e4e7ec;border-radius:12px;padding:14px 18px;min-width:150px;}';
    out{end+1} = '.card .n{font-size:26px;font-weight:700;color:#1d4ed8;}.card .l{font-size:12px;color:#667085;}';
    out{end+1} = '.panel{background:#fff;border:1px solid #e4e7ec;border-radius:12px;padding:18px;margin:14px 0;overflow:auto;}';
    out{end+1} = 'table{border-collapse:collapse;width:100%;font-size:13px;}';
    out{end+1} = 'th,td{border-bottom:1px solid #eaecf0;padding:8px 9px;text-align:left;vertical-align:top;}';
    out{end+1} = 'th{background:#f9fafb;color:#475467;font-weight:600;white-space:nowrap;}';
    out{end+1} = 'code{background:#f2f4f7;border-radius:5px;padding:2px 5px;font-family:Consolas,monospace;}';
    out{end+1} = '.changed{background:#eff6ff;}.old{color:#98a2b3;text-decoration:line-through;}.new{color:#1d4ed8;font-weight:600;}';
    out{end+1} = '.grid2{display:grid;grid-template-columns:1fr 1fr;gap:16px;}';
    out{end+1} = 'figure{margin:0;}figure img{max-width:100%;border:1px solid #e4e7ec;border-radius:8px;background:#fff;}';
    out{end+1} = 'figcaption{font-size:12px;color:#667085;margin-top:6px;}';
    out{end+1} = '.muted{color:#98a2b3;}';
    out{end+1} = '</style></head><body><div class="wrap">';
    out{end+1} = mps.tr('<h1>运行对比报告</h1>', ...
        '<h1>Run comparison report</h1>');
    out{end+1} = sprintf(mps.tr( ...
        '<div class="sub">A：%s<br>B：%s<br>生成时间：%s</div>', ...
        '<div class="sub">A: %s<br>B: %s<br>Generated: %s</div>'), ...
        htmlEscape(dirA), htmlEscape(dirB), stamp);

    out{end+1} = '<div class="cards">';
    out{end+1} = sprintf(mps.tr( ...
        '<div class="card"><div class="n">%d</div><div class="l">参数差异</div></div>', ...
        '<div class="card"><div class="n">%d</div><div class="l">Parameter differences</div></div>'), nChanged);
    out{end+1} = sprintf(mps.tr( ...
        '<div class="card"><div class="n">%d</div><div class="l">数值有差异的变量</div></div>', ...
        '<div class="card"><div class="n">%d</div><div class="l">Variables with numeric differences</div></div>'), nDiffVars);
    out{end+1} = sprintf(mps.tr( ...
        '<div class="card"><div class="n">%d</div><div class="l">A 输出图</div></div>', ...
        '<div class="card"><div class="n">%d</div><div class="l">A figures</div></div>'), numel(figA));
    out{end+1} = sprintf(mps.tr( ...
        '<div class="card"><div class="n">%d</div><div class="l">B 输出图</div></div>', ...
        '<div class="card"><div class="n">%d</div><div class="l">B figures</div></div>'), numel(figB));
    out{end+1} = '</div>';

    % Parameters table
    out{end+1} = mps.tr('<h2>参数对比</h2><div class="panel">', ...
        '<h2>Parameter comparison</h2><div class="panel">');
    if isempty(paramDiffs)
        out{end+1} = mps.tr( ...
            '<p class="muted">两次运行都没有参数记录。</p>', ...
            '<p class="muted">Neither run has a parameter record.</p>');
    else
        out{end+1} = mps.tr( ...
            '<table><thead><tr><th>参数</th><th>行 (A / B)</th><th>A 运行值</th><th>B 运行值</th><th>说明</th></tr></thead><tbody>', ...
            '<table><thead><tr><th>Parameter</th><th>Line (A / B)</th><th>A run value</th><th>B run value</th><th>Note</th></tr></thead><tbody>');
        for k = 1:numel(paramDiffs)
            d = paramDiffs(k);
            rowClass = '';
            if d.changed, rowClass = ' class="changed"'; end
            if strcmp(d.only, 'A')
                note = mps.tr('仅 A 有', 'Only in A');
            elseif strcmp(d.only, 'B')
                note = mps.tr('仅 B 有', 'Only in B');
            elseif d.changed
                note = sprintf('<span class="old">%s</span> → <span class="new">%s</span>', ...
                    htmlEscape(d.valueA), htmlEscape(d.valueB));
            else
                note = mps.tr('相同', 'Same');
            end
            out{end+1} = sprintf('<tr%s><td><code>%s</code></td><td>%s / %s</td><td>%s</td><td>%s</td><td>%s</td></tr>', ...
                rowClass, htmlEscape(d.name), fmtLine(d.lineA), ...
                fmtLine(d.lineB), htmlEscape(d.valueA), ...
                htmlEscape(d.valueB), note); %#ok<AGROW>
        end
        out{end+1} = '</tbody></table>';
    end
    out{end+1} = '</div>';

    % Workspace table
    out{end+1} = mps.tr('<h2>工作区变量对比</h2><div class="panel">', ...
        '<h2>Workspace variable comparison</h2><div class="panel">');
    if isempty(common)
        out{end+1} = mps.tr( ...
            '<p class="muted">没有同名的工作区变量。</p>', ...
            '<p class="muted">No workspace variables with the same name.</p>');
    else
        out{end+1} = mps.tr( ...
            '<table><thead><tr><th>变量</th><th>大小 (A/B)</th><th>状态</th><th>最大绝对差</th><th>RMS 差</th><th>相对差</th></tr></thead><tbody>', ...
            '<table><thead><tr><th>Variable</th><th>Size (A/B)</th><th>Status</th><th>Max abs diff</th><th>RMS diff</th><th>Relative diff</th></tr></thead><tbody>');
        for k = 1:numel(wsDiffs)
            d = wsDiffs(k);
            out{end+1} = sprintf('<tr><td><code>%s</code></td><td>%s / %s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>', ...
                htmlEscape(d.name), htmlEscape(d.sizeA), htmlEscape(d.sizeB), ...
                htmlEscape(d.status), fmtNum(d.maxAbs), fmtNum(d.rms), fmtPercent(d.rel)); %#ok<AGROW>
        end
        out{end+1} = '</tbody></table>';
    end
    if ~isempty(onlyA)
        out{end+1} = sprintf(mps.tr( ...
            '<p class="muted">仅 A 有：%s</p>', ...
            '<p class="muted">Only in A: %s</p>'), ...
            htmlEscape(strjoin(onlyA, ', ')));
    end
    if ~isempty(onlyB)
        out{end+1} = sprintf(mps.tr( ...
            '<p class="muted">仅 B 有：%s</p>', ...
            '<p class="muted">Only in B: %s</p>'), ...
            htmlEscape(strjoin(onlyB, ', ')));
    end
    out{end+1} = '</div>';

    % Figures
    out{end+1} = mps.tr( ...
        '<h2>输出图对比</h2><div class="panel"><div class="grid2">', ...
        '<h2>Figure comparison</h2><div class="panel"><div class="grid2">');
    nFig = max(numel(assetsA), numel(assetsB));
    for k = 1:nFig
        out{end+1} = '<div>';
        if k <= numel(assetsA)
            out{end+1} = sprintf(mps.tr( ...
                '<figure><img src="%s" alt="A 图 %d"><figcaption>A · %s</figcaption></figure>', ...
                '<figure><img src="%s" alt="A figure %d"><figcaption>A · %s</figcaption></figure>'), ...
                htmlEscape(relativePath(outDir, assetsA{k})), k, htmlEscape(figName(figA, k))); %#ok<AGROW>
        else
            out{end+1} = mps.tr( ...
                '<p class="muted">（A 没有更多图）</p>', ...
                '<p class="muted">(A has no more figures)</p>');
        end
        out{end+1} = '</div><div>';
        if k <= numel(assetsB)
            out{end+1} = sprintf(mps.tr( ...
                '<figure><img src="%s" alt="B 图 %d"><figcaption>B · %s</figcaption></figure>', ...
                '<figure><img src="%s" alt="B figure %d"><figcaption>B · %s</figcaption></figure>'), ...
                htmlEscape(relativePath(outDir, assetsB{k})), k, htmlEscape(figName(figB, k))); %#ok<AGROW>
        else
            out{end+1} = mps.tr( ...
                '<p class="muted">（B 没有更多图）</p>', ...
                '<p class="muted">(B has no more figures)</p>');
        end
        out{end+1} = '</div>';
    end
    out{end+1} = '</div></div>';

    out{end+1} = mps.tr( ...
        '<p class="muted">由 MATLAB Parameter Studio 生成 · mps.compareRuns</p>', ...
        '<p class="muted">Generated by MATLAB Parameter Studio · mps.compareRuns</p>');
    out{end+1} = '</div></body></html>';

    for k = 1:numel(out)
        fprintf(fid, '%s\n', out{k});
    end

    % --- JSON sidecar ----------------------------------------------------
    data = struct();
    data.dirA = dirA;
    data.dirB = dirB;
    data.created = stamp;
    data.parameterDiffs = paramDiffs;
    data.workspaceDiffs = wsDiffs;
    data.onlyA = onlyA;
    data.onlyB = onlyB;
    jsonPath = fullfile(outDir, 'compare.json');
    fid2 = fopen(jsonPath, 'w', 'n', 'UTF-8');
    if fid2 >= 0
        try
            fprintf(fid2, '%s', jsonencode(data, 'PrettyPrint', true));
        catch
            fprintf(fid2, '%s', jsonencode(data));
        end
        fclose(fid2);
    end
end

% -------------------------------------------------------------------------
function p = loadParams(dir)
    p = struct('name', {}, 'line', {}, 'value', {}, 'newValue', {}, ...
        'use', {}, 'locked', {});
    f = fullfile(dir, 'parameters.json');
    if ~isfile(f)
        return;
    end
    try
        raw = jsondecode(fileread(f));
    catch err
        mps.logWarning(mps.tr('读取运行参数对比 JSON', ...
            'Read run parameter comparison JSON'), err);
        return;
    end
    if ~isstruct(raw) || isempty(raw)
        return;
    end
    for k = 1:numel(raw)
        item = struct();
        item.name = charField(raw(k), 'name');
        item.line = numberField(raw(k), 'line');
        item.value = charField(raw(k), 'value');
        item.newValue = charField(raw(k), 'newValue');
        item.use = logicalField(raw(k), 'use');
        item.locked = logicalField(raw(k), 'locked');
        p(end+1) = item; %#ok<AGROW>
    end
end

% -------------------------------------------------------------------------
function v = charField(s, name)
    v = '';
    if isfield(s, name)
        x = s.(name);
        if ischar(x)
            v = x;
        elseif isstring(x) && isscalar(x)
            v = char(x);
        end
    end
end

% -------------------------------------------------------------------------
function v = logicalField(s, name)
    v = false;
    if isfield(s, name)
        x = s.(name);
        if islogical(x) || isnumeric(x)
            v = logical(x(1));
        end
    end
end

% -------------------------------------------------------------------------
function v = numberField(s, name)
    v = NaN;
    if isfield(s, name)
        x = s.(name);
        if isnumeric(x) && isscalar(x)
            v = double(x);
        end
    end
end

% -------------------------------------------------------------------------
function keys = parameterKeys(p)
    keys = cell(1, numel(p));
    for k = 1:numel(p)
        if isnan(p(k).line)
            keys{k} = p(k).name;
        else
            keys{k} = sprintf('%s|%d', p(k).name, p(k).line);
        end
    end
end

% -------------------------------------------------------------------------
function s = fmtLine(v)
    if isempty(v) || isnan(v)
        s = '-';
    else
        s = sprintf('%d', v);
    end
end

% -------------------------------------------------------------------------
function v = effectiveValue(p)
    v = p.value;
    if p.use && ~p.locked && ~isempty(p.newValue)
        v = p.newValue;
    end
end

% -------------------------------------------------------------------------
function S = loadWorkspace(runDir)
    S = struct();
    f = fullfile(runDir, 'workspace.mat');
    if ~isfile(f)
        return;
    end

    % Load only variables that can be compared.  Function handles and
    % graphics objects are skipped: loading them can emit confusing
    % "cannot find function" warnings and they have no numeric diff.
    skipClasses = {'function_handle', 'matlab.ui.Figure', ...
        'matlab.graphics.Graphics', 'matlab.graphics.axis.Axes'};
    try
        info = whos('-file', f);
    catch err
        mps.logWarning(mps.tr('读取对比工作区变量列表', ...
            'Read comparison workspace variable list'), err);
        return;
    end
    keep = {};
    for k = 1:numel(info)
        cls = info(k).class;
        if any(strcmp(cls, skipClasses))
            continue;
        end
        if startsWith(cls, 'matlab.ui.') || startsWith(cls, 'matlab.graphics.')
            continue;
        end
        keep{end+1} = info(k).name; %#ok<AGROW>
    end
    if isempty(keep)
        return;
    end

    oldWarning = warning('off', 'all');
    cleaner = onCleanup(@() warning(oldWarning)); %#ok<NASGU>
    try
        S = load(f, keep{:});
    catch err
        S = struct();
        mps.logWarning(mps.tr('读取对比工作区变量', ...
            'Read comparison workspace variables'), err);
    end
end

% -------------------------------------------------------------------------
function figs = listFigures(runDir)
    figs = {};
    figDir = fullfile(runDir, 'figures');
    if ~isfolder(figDir)
        return;
    end
    d = dir(fullfile(figDir, '*.png'));
    [~, order] = sort({d.name});
    d = d(order);
    for k = 1:numel(d)
        figs{end+1} = fullfile(d(k).folder, d(k).name); %#ok<AGROW>
    end
end

% -------------------------------------------------------------------------
function name = figName(figs, k)
    name = mps.tr('图 %d', 'Figure %d', k);
    if k <= numel(figs)
        [~, base] = fileparts(figs{k});
        name = base;
    end
end

% -------------------------------------------------------------------------
function assets = copyFigureSet(figs, assetDir, prefix)
    assets = {};
    for k = 1:numel(figs)
        target = fullfile(assetDir, sprintf('%s_%02d.png', prefix, k));
        try
            copyfile(figs{k}, target);
            assets{end+1} = target; %#ok<AGROW>
        catch err
            assets{end+1} = figs{k}; %#ok<AGROW>
            mps.logWarning(mps.tr('复制对比图窗', ...
                'Copy comparison figures'), err);
        end
    end
end

% -------------------------------------------------------------------------
function s = sizeString(sz)
    parts = arrayfun(@(x) num2str(x), sz, 'UniformOutput', false);
    s = strjoin(parts, 'x');
end

% -------------------------------------------------------------------------
function s = fmtNum(v)
    if isempty(v) || (isnumeric(v) && any(isnan(v)))
        s = '';
    elseif isnumeric(v)
        s = num2str(v, '%.6g');
    else
        s = char(v);
    end
end

% -------------------------------------------------------------------------
function s = fmtPercent(v)
    if isempty(v) || (isnumeric(v) && any(isnan(v)))
        s = '';
    elseif isnumeric(v)
        s = sprintf('%.3g%%', v * 100);
    else
        s = char(v);
    end
end

% -------------------------------------------------------------------------
function s = htmlEscape(s)
    if isempty(s)
        s = '';
        return;
    end
    s = char(s);
    s = strrep(s, '&', '&amp;');
    s = strrep(s, '<', '&lt;');
    s = strrep(s, '>', '&gt;');
    s = strrep(s, '"', '&quot;');
    s = strrep(s, '''', '&#39;');
end

% -------------------------------------------------------------------------
function s = relativePath(baseDir, filePath)
    s = char(filePath);
    base = char(baseDir);
    if startsWith(s, base)
        s = s(numel(base)+1:end);
        s = regexprep(s, '^[\\/]+', '');
    end
    s = strrep(s, '\', '/');
end
