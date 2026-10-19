function reportPath = writeSweepReport(sweepRoot, sourceFile, names, values, ...
    scenarios, results, overlayPath)
%WRITESWEEPREPORT HTML report for a completed parameter sweep.
%
%   reportPath = mps.writeSweepReport(sweepRoot, sourceFile, names, values, ...
%       scenarios, results, overlayPath)
%
%   names     - cell array of swept parameter names
%   values    - cell array of numeric value lists
%   scenarios - struct array from mps.sweepScenarios
%   results   - struct array with fields label, runDir, ok, error,
%               figures, elapsed

    if nargin < 7
        overlayPath = '';
    end
    reportPath = fullfile(sweepRoot, 'sweep_report.html');
    fid = fopen(reportPath, 'w', 'n', 'UTF-8');
    if fid < 0
        error('mps:writeSweepReport:cannotWrite', '无法写入：%s', reportPath);
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

    nFig = 0;
    nFail = 0;
    for k = 1:numel(results)
        nFig = nFig + numel(results(k).figures);
        if ~results(k).ok
            nFail = nFail + 1;
        end
    end

    stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    out = {};
    out{end+1} = '<!DOCTYPE html>';
    out{end+1} = '<html lang="zh-CN"><head><meta charset="utf-8">';
    out{end+1} = '<meta name="viewport" content="width=device-width, initial-scale=1">';
    out{end+1} = '<title>批量扫描报告</title>';
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
    out{end+1} = '.ok{color:#067647;font-weight:600;}.bad{color:#b42318;font-weight:600;}';
    out{end+1} = '.err{color:#b42318;font-family:Consolas,monospace;font-size:12px;white-space:pre-wrap;}';
    out{end+1} = 'figure{margin:0 0 14px;}figure img{max-width:100%;border:1px solid #e4e7ec;border-radius:8px;background:#fff;}';
    out{end+1} = 'figcaption{font-size:12px;color:#667085;margin-top:4px;}';
    out{end+1} = '.grid2{display:grid;grid-template-columns:1fr 1fr;gap:14px;}';
    out{end+1} = '.muted{color:#98a2b3;}';
    out{end+1} = '</style></head><body><div class="wrap">';
    out{end+1} = '<h1>批量扫描报告</h1>';
    out{end+1} = sprintf('<div class="sub">源文件：<code>%s</code><br>扫描参数：%s<br>生成时间：%s</div>', ...
        htmlEscape(sourceFile), htmlEscape(valueListText(names, values)), stamp);

    out{end+1} = '<div class="cards">';
    out{end+1} = sprintf('<div class="card"><div class="n">%d</div><div class="l">扫描组数</div></div>', numel(results));
    out{end+1} = sprintf('<div class="card"><div class="n">%d</div><div class="l">扫描参数</div></div>', numel(names));
    out{end+1} = sprintf('<div class="card"><div class="n">%d</div><div class="l">输出图</div></div>', nFig);
    out{end+1} = sprintf('<div class="card"><div class="n">%d</div><div class="l">失败组数</div></div>', nFail);
    out{end+1} = '</div>';

    % Scenario table
    out{end+1} = '<h2>扫描组</h2><div class="panel">';
    out{end+1} = '<table><thead><tr><th>#</th><th>参数取值</th><th>状态</th><th>耗时 (s)</th><th>图数</th><th>运行目录</th></tr></thead><tbody>';
    for k = 1:numel(results)
        r = results(k);
        if r.ok
            status = '<span class="ok">成功</span>';
        else
            status = '<span class="bad">失败</span>';
        end
        out{end+1} = sprintf('<tr><td>%d</td><td><code>%s</code></td><td>%s</td><td>%.2f</td><td>%d</td><td><code>%s</code></td></tr>', ...
            k, htmlEscape(r.label), status, r.elapsed, ...
            numel(r.figures), htmlEscape(relativePath(sweepRoot, r.runDir))); %#ok<AGROW>
        if ~r.ok && ~isempty(r.error)
            out{end+1} = sprintf('<tr><td></td><td colspan="5" class="err">%s</td></tr>', ...
                htmlEscape(firstLines(r.error, 6))); %#ok<AGROW>
        end
    end
    out{end+1} = '</tbody></table></div>';

    % Overlay
    if ~isempty(overlayPath) && isfile(overlayPath)
        out{end+1} = '<h2>叠加曲线</h2><div class="panel">';
        out{end+1} = sprintf('<figure><img src="%s" alt="叠加曲线"><figcaption>%s</figcaption></figure>', ...
            htmlEscape(relativePath(sweepRoot, overlayPath)), ...
            htmlEscape(valueListText(names, values)));
        out{end+1} = '</div>';
    end

    % Per-scenario figures
    out{end+1} = '<h2>各组输出图</h2><div class="panel">';
    for k = 1:numel(results)
        r = results(k);
        out{end+1} = sprintf('<h3>%d. %s</h3>', k, htmlEscape(r.label)); %#ok<AGROW>
        if isempty(r.figures)
            out{end+1} = '<p class="muted">本组没有输出图。</p>'; %#ok<AGROW>
        else
            out{end+1} = '<div class="grid2">'; %#ok<AGROW>
            for j = 1:numel(r.figures)
                f = r.figures(j);
                out{end+1} = sprintf('<figure><img src="%s" alt="%s"><figcaption>%s</figcaption></figure>', ...
                    htmlEscape(relativePath(sweepRoot, f.path)), ...
                    htmlEscape(f.title), htmlEscape(f.title)); %#ok<AGROW>
            end
            out{end+1} = '</div>'; %#ok<AGROW>
        end
    end
    out{end+1} = '</div>';

    out{end+1} = '<p class="muted">由 MATLAB Parameter Studio 生成 · mps.writeSweepReport</p>';
    out{end+1} = '</div></body></html>';

    for k = 1:numel(out)
        fprintf(fid, '%s\n', out{k});
    end

    % JSON sidecar
    data = struct();
    data.sourceFile = sourceFile;
    data.created = stamp;
    data.names = names;
    data.values = values;
    data.scenarios = scenarios;
    slim = struct('label', {}, 'runDir', {}, 'ok', {}, 'elapsed', {}, 'figureCount', {});
    for k = 1:numel(results)
        slim(end+1) = struct('label', results(k).label, ...
            'runDir', results(k).runDir, 'ok', results(k).ok, ...
            'elapsed', results(k).elapsed, ...
            'figureCount', numel(results(k).figures)); %#ok<AGROW>
    end
    data.results = slim;
    jsonPath = fullfile(sweepRoot, 'sweep.json');
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
function s = valueListText(names, values)
    parts = cell(1, numel(names));
    for k = 1:numel(names)
        v = values{k};
        if numel(v) <= 8
            list = strjoin(arrayfun(@(x) num2str(x, '%.6g'), v, ...
                'UniformOutput', false), ', ');
        else
            list = sprintf('%d 个值（%s … %s）', numel(v), ...
                num2str(v(1), '%.6g'), num2str(v(end), '%.6g'));
        end
        parts{k} = sprintf('%s = %s', names{k}, list);
    end
    s = strjoin(parts, '；');
end

% -------------------------------------------------------------------------
function s = firstLines(txt, n)
    lines = regexp(char(txt), '\n', 'split');
    if numel(lines) > n
        lines = lines(1:n);
        lines{end+1} = '...';
    end
    s = strjoin(lines, sprintf('\n'));
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
