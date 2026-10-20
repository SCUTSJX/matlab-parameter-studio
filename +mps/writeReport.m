function reportPath = writeReport(outDir, sourceFile, params, result)
%WRITEREPORT Create an HTML report and a JSON parameter record.
%
%   reportPath = mps.writeReport(outDir, sourceFile, params, result)

    if ~isfolder(outDir)
        mkdir(outDir);
    end

    used = params(false(size(params)));
    if ~isempty(params)
        used = params([params.use]);
    end

    changedCount = 0;
    for k = 1:numel(used)
        if ~strcmp(strtrim(used(k).value), strtrim(used(k).newValue))
            changedCount = changedCount + 1;
        end
    end

    reportPath = fullfile(outDir, 'report.html');
    fid = fopen(reportPath, 'w', 'n', 'UTF-8');
    if fid < 0
        error('mps:writeReport:cannotWrite', mps.tr( ...
            '无法写入报告：%s', 'Cannot write report: %s'), reportPath);
    end
    cleaner = onCleanup(@() fclose(fid));

    stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    matlabVersion = version;
    statusText = mps.tr('成功', 'Success');
    statusClass = 'ok';
    if ~result.ok
        statusText = mps.tr('运行失败', 'Run failed');
        statusClass = 'bad';
    end
    elapsed = 0;
    if isfield(result, 'elapsedSeconds')
        elapsed = result.elapsedSeconds;
    end

    out = {};
    out{end+1} = '<!DOCTYPE html>';
    out{end+1} = mps.tr('<html lang="zh-CN">', '<html lang="en">');
    out{end+1} = '<head>';
    out{end+1} = '<meta charset="utf-8">';
    out{end+1} = '<meta name="viewport" content="width=device-width, initial-scale=1">';
    out{end+1} = mps.tr( ...
        '<title>MATLAB Parameter Studio 运行报告</title>', ...
        '<title>MATLAB Parameter Studio Run Report</title>');
    out{end+1} = '<style>';
    out{end+1} = 'body{font-family:"Microsoft YaHei","Segoe UI",Arial,sans-serif;margin:0;background:#f5f7fb;color:#172033;line-height:1.55;}';
    out{end+1} = '.wrap{max-width:1100px;margin:0 auto;padding:32px 24px 60px;}';
    out{end+1} = 'h1{font-size:28px;margin:0 0 6px;font-weight:650;}';
    out{end+1} = 'h2{font-size:19px;margin:30px 0 12px;border-left:4px solid #3b82f6;padding-left:10px;}';
    out{end+1} = '.sub{color:#667085;margin-bottom:24px;}';
    out{end+1} = '.cards{display:flex;gap:14px;flex-wrap:wrap;margin:22px 0 6px;}';
    out{end+1} = '.card{background:#fff;border:1px solid #e4e7ec;border-radius:12px;padding:14px 18px;min-width:150px;box-shadow:0 1px 2px rgba(16,24,40,.04);}';
    out{end+1} = '.card .n{font-size:26px;font-weight:700;color:#1d4ed8;}';
    out{end+1} = '.card .l{font-size:12px;color:#667085;}';
    out{end+1} = '.panel{background:#fff;border:1px solid #e4e7ec;border-radius:12px;padding:18px;margin:14px 0;box-shadow:0 1px 2px rgba(16,24,40,.04);overflow:auto;}';
    out{end+1} = 'table{border-collapse:collapse;width:100%;font-size:13px;}';
    out{end+1} = 'th,td{border-bottom:1px solid #eaecf0;padding:8px 9px;text-align:left;vertical-align:top;}';
    out{end+1} = 'th{background:#f9fafb;color:#475467;font-weight:600;white-space:nowrap;}';
    out{end+1} = 'tr:last-child td{border-bottom:0;}';
    out{end+1} = 'code{background:#f2f4f7;border-radius:5px;padding:2px 5px;font-family:Consolas,"Courier New",monospace;}';
    out{end+1} = '.changed{background:#eff6ff;}';
    out{end+1} = '.old{color:#98a2b3;text-decoration:line-through;}';
    out{end+1} = '.new{color:#1d4ed8;font-weight:600;}';
    out{end+1} = '.ok{color:#067647;}.bad{color:#b42318;}';
    out{end+1} = '.err{background:#fef3f2;border:1px solid #fecdca;color:#b42318;border-radius:10px;padding:14px;white-space:pre-wrap;font-family:Consolas,monospace;font-size:12px;}';
    out{end+1} = 'figure{margin:0 0 22px;}';
    out{end+1} = 'figure img{max-width:100%;border:1px solid #e4e7ec;border-radius:8px;background:#fff;}';
    out{end+1} = 'figcaption{font-size:12px;color:#667085;margin-top:6px;}';
    out{end+1} = 'pre{background:#101828;color:#e4e7ec;border-radius:10px;padding:14px;overflow:auto;font-size:12px;line-height:1.45;}';
    out{end+1} = '.muted{color:#98a2b3;}';
    out{end+1} = '</style>';
    out{end+1} = '</head>';
    out{end+1} = '<body><div class="wrap">';
    out{end+1} = mps.tr( ...
        '<h1>MATLAB Parameter Studio 运行报告</h1>', ...
        '<h1>MATLAB Parameter Studio Run Report</h1>');
    out{end+1} = sprintf(mps.tr( ...
        '<div class="sub">源文件：<code>%s</code><br>运行时间：%s　状态：<b class="%s">%s</b>　耗时：%.2f s</div>', ...
        '<div class="sub">Source: <code>%s</code><br>Run time: %s　Status: <b class="%s">%s</b>　Elapsed: %.2f s</div>'), ...
        htmlEscape(sourceFile), stamp, statusClass, statusText, elapsed);

    out{end+1} = '<div class="cards">';
    out{end+1} = sprintf(mps.tr( ...
        '<div class="card"><div class="n">%d</div><div class="l">识别参数总数</div></div>', ...
        '<div class="card"><div class="n">%d</div><div class="l">Parameters found</div></div>'), numel(params));
    out{end+1} = sprintf(mps.tr( ...
        '<div class="card"><div class="n">%d</div><div class="l">本次参与运行</div></div>', ...
        '<div class="card"><div class="n">%d</div><div class="l">Used in this run</div></div>'), numel(used));
    out{end+1} = sprintf(mps.tr( ...
        '<div class="card"><div class="n">%d</div><div class="l">已修改参数</div></div>', ...
        '<div class="card"><div class="n">%d</div><div class="l">Parameters changed</div></div>'), changedCount);
    out{end+1} = sprintf(mps.tr( ...
        '<div class="card"><div class="n">%d</div><div class="l">输出图</div></div>', ...
        '<div class="card"><div class="n">%d</div><div class="l">Figures</div></div>'), numel(result.figures));
    out{end+1} = sprintf(mps.tr( ...
        '<div class="card"><div class="n">%d</div><div class="l">工作区变量</div></div>', ...
        '<div class="card"><div class="n">%d</div><div class="l">Workspace variables</div></div>'), numel(result.workspace));
    out{end+1} = '</div>';

    if ~result.ok
        out{end+1} = mps.tr('<h2>运行错误</h2>', '<h2>Run error</h2>');
        out{end+1} = sprintf('<div class="err">%s</div>', htmlEscape(result.error));
    end

    out{end+1} = mps.tr('<h2>参数</h2>', '<h2>Parameters</h2>');
    out{end+1} = '<div class="panel">';
    if isempty(used)
        out{end+1} = mps.tr( ...
            '<p class="muted">本次没有勾选任何参数。脚本仍然按原值运行。</p>', ...
            '<p class="muted">No parameters were selected. The script still runs with its original values.</p>');
    else
        out{end+1} = mps.tr( ...
            '<table><thead><tr><th>参数</th><th>文件</th><th>锁定</th><th>原值</th><th>新值</th><th>行</th><th>类型</th><th>注释</th><th>代码说明</th></tr></thead><tbody>', ...
            '<table><thead><tr><th>Parameter</th><th>File</th><th>Locked</th><th>Original</th><th>New</th><th>Line</th><th>Type</th><th>Note</th><th>Description</th></tr></thead><tbody>');
        for k = 1:numel(used)
            p = used(k);
            changed = ~strcmp(strtrim(p.value), strtrim(p.newValue));
            locked = isfield(p, 'locked') && p.locked;
            rowClass = '';
            if changed, rowClass = ' class="changed"'; end
            if locked
                lockCell = mps.tr('锁', 'Locked');
                nameCell = sprintf(mps.tr('[锁] %s', '[Locked] %s'), ...
                    htmlEscape(p.name));
            else
                lockCell = '';
                nameCell = htmlEscape(p.name);
            end
            if changed
                oldCell = sprintf('<span class="old">%s</span>', htmlEscape(p.value));
                newCell = sprintf('<span class="new">%s</span>', htmlEscape(p.newValue));
            else
                oldCell = htmlEscape(p.value);
                newCell = htmlEscape(p.value);
            end
            fileCell = '';
            if isfield(p, 'sourceFile')
                fileCell = fileName(p.sourceFile);
            end
            out{end+1} = sprintf('<tr%s><td><code>%s</code></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%d</td><td>%s</td><td>%s</td><td>%s</td></tr>', ...
                rowClass, nameCell, htmlEscape(fileCell), lockCell, ...
                oldCell, newCell, p.line, ...
                htmlEscape(categoryLabel(p.category)), ...
                htmlEscape(annotationText(p)), htmlEscape(p.note)); %#ok<AGROW>
        end
        out{end+1} = '</tbody></table>';
    end
    out{end+1} = '</div>';

    out{end+1} = mps.tr('<h2>输出图</h2>', '<h2>Figures</h2>');
    out{end+1} = '<div class="panel">';
    if isempty(result.figures)
        out{end+1} = mps.tr( ...
            '<p class="muted">本次运行没有产生图窗。你可以在工作区里选择变量，用“绘图”标签手动生成一张图。</p>', ...
            '<p class="muted">This run produced no figures. You can select workspace variables and create one manually on the “Plot” tab.</p>');
    else
        for k = 1:numel(result.figures)
            f = result.figures(k);
            rel = relativePath(outDir, f.path);
            out{end+1} = sprintf('<figure><img src="%s" alt="%s"><figcaption>%s</figcaption></figure>', ...
                htmlEscape(rel), htmlEscape(f.title), htmlEscape(f.title)); %#ok<AGROW>
        end
    end
    out{end+1} = '</div>';

    out{end+1} = mps.tr('<h2>工作区变量</h2>', '<h2>Workspace variables</h2>');
    out{end+1} = '<div class="panel">';
    if isempty(result.workspace)
        out{end+1} = mps.tr( ...
            '<p class="muted">没有捕获到工作区变量。</p>', ...
            '<p class="muted">No workspace variables were captured.</p>');
    else
        out{end+1} = mps.tr( ...
            '<table><thead><tr><th>变量</th><th>类型</th><th>大小</th><th>最小值</th><th>最大值</th><th>预览</th></tr></thead><tbody>', ...
            '<table><thead><tr><th>Variable</th><th>Type</th><th>Size</th><th>Min</th><th>Max</th><th>Preview</th></tr></thead><tbody>');
        for k = 1:numel(result.workspace)
            w = result.workspace(k);
            out{end+1} = sprintf('<tr><td><code>%s</code></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>', ...
                htmlEscape(w.name), htmlEscape(w.class), htmlEscape(w.size), ...
                htmlEscape(fmtValue(w.min)), htmlEscape(fmtValue(w.max)), ...
                htmlEscape(w.preview)); %#ok<AGROW>
        end
        out{end+1} = '</tbody></table>';
    end
    out{end+1} = '</div>';

    out{end+1} = mps.tr('<h2>控制台输出</h2>', '<h2>Console output</h2>');
    out{end+1} = '<div class="panel">';
    if isempty(result.log)
        out{end+1} = mps.tr( ...
            '<p class="muted">没有控制台输出。</p>', ...
            '<p class="muted">No console output.</p>');
    else
        out{end+1} = sprintf('<pre>%s</pre>', htmlEscape(result.log));
    end
    out{end+1} = '</div>';

    out{end+1} = mps.tr('<h2>如何复现</h2>', '<h2>How to reproduce</h2>');
    out{end+1} = '<div class="panel">';
    out{end+1} = sprintf(mps.tr( ...
        '<p>本次使用的脚本副本：<code>%s</code></p>', ...
        '<p>Script copy used in this run: <code>%s</code></p>'), ...
        htmlEscape(relativePath(outDir, result.scriptPath)));
    out{end+1} = sprintf(mps.tr( ...
        '<p>参数记录：<code>parameters.json</code>　工作区：<code>%s</code></p>', ...
        '<p>Parameter record: <code>parameters.json</code>　Workspace: <code>%s</code></p>'), ...
        htmlEscape(ifelse(result.matFile, relativePath(outDir, result.matFile), ...
        mps.tr('未生成', 'Not generated'))));
    out{end+1} = mps.tr( ...
        '<p class="muted">提示：生成的脚本保留了原文件的行号；应用在运行时把 <code>close all</code> 替换成了无害语句，以便捕获图窗。</p>', ...
        '<p class="muted">Note: the generated script keeps the original line numbers; at run time the app replaces <code>close all</code> with a harmless statement so figures can be captured.</p>');
    out{end+1} = '</div>';

    out{end+1} = sprintf(mps.tr( ...
        '<p class="muted">由 MATLAB Parameter Studio 生成 · MATLAB %s</p>', ...
        '<p class="muted">Generated by MATLAB Parameter Studio · MATLAB %s</p>'), ...
        htmlEscape(matlabVersion));
    out{end+1} = '</div></body></html>';

    for k = 1:numel(out)
        fprintf(fid, '%s\n', out{k});
    end

    % Parameter record for later reuse / audits.
    record = struct('id', {}, 'name', {}, 'value', {}, 'newValue', {}, ...
        'use', {}, 'line', {}, 'category', {}, 'note', {}, ...
        'description', {}, 'unit', {}, 'locked', {}, 'sourceFile', {});
    for k = 1:numel(params)
        [description, unit, locked] = localFields(params(k));
        sourceFile = '';
        if isfield(params(k), 'sourceFile')
            sourceFile = params(k).sourceFile;
        end
        record(end+1) = struct('id', idField(params(k)), ...
            'name', params(k).name, 'value', params(k).value, ...
            'newValue', params(k).newValue, 'use', params(k).use, ...
            'line', params(k).line, 'category', params(k).category, ...
            'note', params(k).note, 'description', description, ...
            'unit', unit, 'locked', locked, ...
            'sourceFile', sourceFile); %#ok<AGROW>
    end
    jsonPath = fullfile(outDir, 'parameters.json');
    fid2 = fopen(jsonPath, 'w', 'n', 'UTF-8');
    if fid2 >= 0
        fprintf(fid2, '%s', jsonencode(record));
        fclose(fid2);
    else
        mps.logWarning(mps.tr('写入参数 JSON', 'Write parameter JSON'), ...
            mps.tr('无法创建 %s', 'Cannot create %s', jsonPath));
    end

    try
        save(fullfile(outDir, 'parameters.mat'), 'params');
    catch err
        mps.logWarning(mps.tr('写入 parameters.mat', ...
            'Write parameters.mat'), err);
    end

    % Machine-readable run record used by the run history browser.
    resultOk = false;
    resultError = '';
    if isfield(result, 'ok'), resultOk = logical(result.ok); end
    if isfield(result, 'error'), resultError = char(result.error); end
    meta = struct( ...
        'sourceFile', sourceFile, ...
        'created', stamp, ...
        'ok', resultOk, ...
        'error', resultError, ...
        'elapsedSeconds', elapsed, ...
        'figureCount', numel(result.figures), ...
        'workspaceCount', numel(result.workspace), ...
        'matlabVersion', matlabVersion, ...
        'isSweep', false);
    writeRunJson(fullfile(outDir, 'run.json'), meta);
end

% -------------------------------------------------------------------------
function s = idField(p)
    s = '';
    if isfield(p, 'id')
        s = char(p.id);
    end
end

% -------------------------------------------------------------------------
function writeRunJson(path, meta)
    try
        fid = fopen(path, 'w', 'n', 'UTF-8');
        if fid < 0
            return;
        end
        cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
        fprintf(fid, '%s', jsonencode(meta));
        clear cleaner;
    catch err
        mps.logWarning(mps.tr('写入运行摘要 JSON', ...
            'Write run summary JSON'), err);
    end
end

% -------------------------------------------------------------------------
function name = fileName(path)
    [~, base, ext] = fileparts(char(path));
    name = [base ext];
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
function [description, unit, locked] = localFields(p)
    description = '';
    unit = '';
    locked = false;
    if isfield(p, 'description'), description = p.description; end
    if isfield(p, 'unit'), unit = p.unit; end
    if isfield(p, 'locked'), locked = p.locked; end
end

% -------------------------------------------------------------------------
function s = annotationText(p)
%ANNOTATIONTEXT Format the AI annotation for the report table.
    s = '';
    if isfield(p, 'description')
        s = p.description;
    end
    if isfield(p, 'unit') && ~isempty(p.unit)
        if isempty(s)
            s = ['[' p.unit ']'];
        else
            s = sprintf('%s (%s)', s, p.unit);
        end
    end
end

% -------------------------------------------------------------------------
function s = categoryLabel(c)
    switch c
        case 'assignment', s = mps.tr('赋值', 'Assignment');
        case 'struct', s = mps.tr('结构体字段', 'Struct field');
        case 'array', s = mps.tr('数组元素', 'Array element');
        case 'range', s = mps.tr('范围', 'Range');
        case 'expression', s = mps.tr('表达式', 'Expression');
        case 'argument', s = mps.tr('函数参数', 'Function argument');
        case 'index', s = mps.tr('索引', 'Index');
        case 'style', s = mps.tr('绘图样式', 'Plot style');
        case 'layout', s = mps.tr('界面布局', 'UI layout');
        case 'size', s = mps.tr('数组尺寸', 'Array size');
        case 'control', s = mps.tr('控制流', 'Control flow');
        case 'function', s = mps.tr('函数体', 'Function body');
        case 'annotated', s = mps.tr('注释标记', 'Annotation marker');
        case 'ignored', s = mps.tr('已忽略', 'Ignored');
        case 'manual', s = mps.tr('手动参数', 'Manual parameter');
        otherwise, s = c;
    end
end

% -------------------------------------------------------------------------
function s = fmtValue(v)
    if isempty(v)
        s = '';
    elseif isnumeric(v) || islogical(v)
        try
            s = num2str(v, '%.6g');
        catch
            s = num2str(v);
        end
    else
        s = char(v);
    end
end

% -------------------------------------------------------------------------
function s = relativePath(baseDir, filePath)
    if isempty(filePath)
        s = '';
        return;
    end
    s = char(filePath);
    base = char(baseDir);
    if startsWith(s, base)
        s = s(numel(base)+1:end);
        s = regexprep(s, '^[\\/]+', '');
    end
    s = strrep(s, '\', '/');
end

% -------------------------------------------------------------------------
function s = ifelse(cond, a, b)
    if cond
        s = a;
    else
        s = b;
    end
end
