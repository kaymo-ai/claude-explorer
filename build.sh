#!/bin/bash
# Build a standalone Claude Explorer HTML with embedded data

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
OUTPUT_FILE="$SCRIPT_DIR/claude-explorer.html"

echo "Building Claude Explorer..."

# Extract data to JSON
extract_data() {
    local json=""

    # Settings
    json+="\"settings\": $(cat "$CLAUDE_DIR/settings.json" 2>/dev/null || echo '{}'),"
    json+="\"settingsLocal\": $(cat "$CLAUDE_DIR/settings.local.json" 2>/dev/null || echo '{}'),"
    json+="\"stats\": $(cat "$CLAUDE_DIR/stats-cache.json" 2>/dev/null || echo '{}'),"
    json+="\"installedPlugins\": $(cat "$CLAUDE_DIR/plugins/installed_plugins.json" 2>/dev/null || echo '{}'),"
    json+="\"marketplaces\": $(cat "$CLAUDE_DIR/plugins/known_marketplaces.json" 2>/dev/null || echo '{}'),"

    # History
    json+="\"history\": ["
    local first=true
    while IFS= read -r line; do
        [ "$first" = true ] && first=false || json+=","
        json+="$line"
    done < "$CLAUDE_DIR/history.jsonl"
    json+="],"

    # Plans
    json+="\"plans\": ["
    first=true
    for plan in "$CLAUDE_DIR/plans/"*.md; do
        [ -f "$plan" ] || continue
        [ "$first" = true ] && first=false || json+=","
        local filename=$(basename "$plan")
        local name="${filename%.md}"
        local size=$(wc -c < "$plan" | tr -d ' ')
        local modified=$(stat -f "%Sm" -t "%Y-%m-%d" "$plan" 2>/dev/null || date -r "$plan" +%Y-%m-%d 2>/dev/null || echo "unknown")
        local content=$(cat "$plan" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
        json+="{\"name\": \"$name\", \"file\": \"$filename\", \"size\": $size, \"modified\": \"$modified\", \"content\": $content}"
    done
    json+="],"

    # Projects
    json+="\"projects\": ["
    first=true
    for proj in "$CLAUDE_DIR/projects/"*/; do
        [ -d "$proj" ] || continue
        [ "$first" = true ] && first=false || json+=","
        local dirname=$(basename "$proj")
        local sessions="["
        local sfirst=true
        for session in "$proj"*.jsonl; do
            [ -f "$session" ] || continue
            [ "$sfirst" = true ] && sfirst=false || sessions+=","
            local sname=$(basename "$session" .jsonl)
            local ssize=$(wc -c < "$session" | tr -d ' ')
            local slines=$(wc -l < "$session" | tr -d ' ')
            sessions+="{\"id\": \"$sname\", \"size\": $ssize, \"lines\": $slines}"
        done
        sessions+="]"
        local session_count=$(ls "$proj"*.jsonl 2>/dev/null | wc -l | tr -d ' ')
        json+="{\"path\": \"$dirname\", \"sessionCount\": $session_count, \"sessions\": $sessions}"
    done
    json+="],"

    # Skills
    json+="\"skills\": ["
    first=true
    for skill in "$CLAUDE_DIR/skills/"*/; do
        [ -d "$skill" ] || continue
        [ "$first" = true ] && first=false || json+=","
        local skillname=$(basename "$skill")
        local skillcontent='""'
        [ -f "$skill/SKILL.md" ] && skillcontent=$(cat "$skill/SKILL.md" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
        local files=$(ls "$skill" 2>/dev/null | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip().split("\n")))')
        json+="{\"name\": \"$skillname\", \"content\": $skillcontent, \"files\": $files}"
    done
    json+="],"

    # Todos
    json+="\"todos\": ["
    first=true
    for todo in "$CLAUDE_DIR/todos/"*.json; do
        [ -f "$todo" ] || continue
        local content=$(cat "$todo" 2>/dev/null)
        [ -z "$content" ] || [ "$content" = "[]" ] && continue
        [ "$first" = true ] && first=false || json+=","
        local todoname=$(basename "$todo" .json)
        json+="{\"id\": \"$todoname\", \"tasks\": $content}"
    done
    json+="],"

    # File History
    json+="\"fileHistory\": ["
    first=true
    for fh in "$CLAUDE_DIR/file-history/"*/; do
        [ -d "$fh" ] || continue
        [ "$first" = true ] && first=false || json+=","
        local fhname=$(basename "$fh")
        local files="["
        local ffirst=true
        for f in "$fh"*; do
            [ -f "$f" ] || continue
            [ "$ffirst" = true ] && ffirst=false || files+=","
            local fname=$(basename "$f")
            local fsize=$(wc -c < "$f" | tr -d ' ')
            files+="{\"name\": \"$fname\", \"size\": $fsize}"
        done
        files+="]"
        local filecount=$(ls "$fh" 2>/dev/null | wc -l | tr -d ' ')
        json+="{\"sessionId\": \"$fhname\", \"fileCount\": $filecount, \"files\": $files}"
    done
    json+="]"

    echo "{$json}"
}

DATA=$(extract_data)

cat > "$OUTPUT_FILE" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Claude Explorer</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
    <style>
        :root {
            --bg-primary: #0d1117;
            --bg-secondary: #161b22;
            --bg-tertiary: #21262d;
            --border: #30363d;
            --text-primary: #e6edf3;
            --text-secondary: #8b949e;
            --accent: #c9885a;
            --accent-hover: #d99a6c;
            --success: #3fb950;
            --warning: #d29922;
            --danger: #f85149;
            --info: #58a6ff;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            min-height: 100vh;
        }
        .container { display: flex; min-height: 100vh; }
        .sidebar {
            width: 260px;
            background: var(--bg-secondary);
            border-right: 1px solid var(--border);
            padding: 20px 0;
            flex-shrink: 0;
            display: flex;
            flex-direction: column;
        }
        .logo { padding: 0 20px 20px; border-bottom: 1px solid var(--border); margin-bottom: 20px; }
        .logo h1 { font-size: 1.5rem; font-weight: 600; color: var(--accent); display: flex; align-items: center; gap: 10px; }
        .logo span { font-size: 0.75rem; color: var(--text-secondary); font-weight: 400; }
        .nav-section { padding: 0 12px; margin-bottom: 24px; }
        .nav-section-title { font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.05em; color: var(--text-secondary); padding: 0 8px; margin-bottom: 8px; }
        .nav-item { display: flex; align-items: center; gap: 12px; padding: 10px 12px; border-radius: 6px; cursor: pointer; color: var(--text-secondary); transition: all 0.15s ease; font-size: 0.9rem; }
        .nav-item:hover { background: var(--bg-tertiary); color: var(--text-primary); }
        .nav-item.active { background: var(--accent); color: white; }
        .nav-item svg { width: 18px; height: 18px; flex-shrink: 0; }
        .nav-item .count { margin-left: auto; background: var(--bg-tertiary); padding: 2px 8px; border-radius: 10px; font-size: 0.7rem; }
        .nav-item.active .count { background: rgba(255,255,255,0.2); }
        .main { flex: 1; padding: 24px; overflow-y: auto; }
        .page { display: none; }
        .page.active { display: block; }
        .page-header { margin-bottom: 24px; }
        .page-header h2 { font-size: 1.5rem; font-weight: 600; margin-bottom: 4px; }
        .page-header p { color: var(--text-secondary); font-size: 0.9rem; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 16px; margin-bottom: 24px; }
        .stat-card { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: 8px; padding: 20px; }
        .stat-card .label { font-size: 0.8rem; color: var(--text-secondary); margin-bottom: 8px; }
        .stat-card .value { font-size: 1.8rem; font-weight: 600; color: var(--accent); }
        .stat-card .subtitle { font-size: 0.75rem; color: var(--text-secondary); margin-top: 4px; }
        .chart-container { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: 8px; padding: 20px; margin-bottom: 24px; }
        .chart-container h3 { font-size: 1rem; margin-bottom: 16px; font-weight: 500; }
        .chart-wrapper { height: 300px; }
        .table-container { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: 8px; overflow: hidden; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 12px 20px; text-align: left; border-bottom: 1px solid var(--border); }
        th { font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; color: var(--text-secondary); font-weight: 500; position: sticky; top: 0; background: var(--bg-secondary); }
        td { font-size: 0.9rem; }
        tr:hover { background: var(--bg-tertiary); }
        tr:last-child td { border-bottom: none; }
        tr.clickable { cursor: pointer; }
        .table-scroll { max-height: 600px; overflow-y: auto; }
        .card-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: 16px; }
        .card { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: 8px; padding: 20px; cursor: pointer; transition: all 0.15s ease; }
        .card:hover { border-color: var(--accent); transform: translateY(-2px); }
        .card-title { font-weight: 500; margin-bottom: 8px; display: flex; align-items: center; gap: 8px; }
        .card-meta { font-size: 0.8rem; color: var(--text-secondary); }
        .card-content { margin-top: 12px; font-size: 0.85rem; color: var(--text-secondary); }
        .badge { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 0.7rem; font-weight: 500; }
        .badge-success { background: rgba(63, 185, 80, 0.2); color: var(--success); }
        .badge-warning { background: rgba(210, 153, 34, 0.2); color: var(--warning); }
        .badge-accent { background: rgba(201, 136, 90, 0.2); color: var(--accent); }
        .badge-info { background: rgba(88, 166, 255, 0.2); color: var(--info); }
        .code-block { background: var(--bg-primary); border: 1px solid var(--border); border-radius: 6px; padding: 16px; font-family: 'Monaco', 'Menlo', monospace; font-size: 0.85rem; overflow-x: auto; white-space: pre-wrap; word-break: break-word; }
        .search-box { display: flex; align-items: center; gap: 8px; background: var(--bg-tertiary); border: 1px solid var(--border); border-radius: 6px; padding: 8px 12px; margin-bottom: 16px; }
        .search-box input { flex: 1; background: none; border: none; color: var(--text-primary); font-size: 0.9rem; outline: none; }
        .search-box svg { color: var(--text-secondary); width: 16px; height: 16px; }
        .filters { display: flex; gap: 8px; margin-bottom: 16px; flex-wrap: wrap; }
        .filter-btn { padding: 6px 12px; background: var(--bg-tertiary); border: 1px solid var(--border); border-radius: 6px; color: var(--text-secondary); font-size: 0.8rem; cursor: pointer; transition: all 0.15s; }
        .filter-btn:hover, .filter-btn.active { background: var(--accent); color: white; border-color: var(--accent); }
        .modal-overlay { display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0, 0, 0, 0.7); z-index: 1000; align-items: center; justify-content: center; }
        .modal-overlay.active { display: flex; }
        .modal { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: 12px; max-width: 900px; max-height: 85vh; width: 95%; overflow: hidden; display: flex; flex-direction: column; }
        .modal-header { padding: 20px; border-bottom: 1px solid var(--border); display: flex; justify-content: space-between; align-items: center; flex-shrink: 0; }
        .modal-header h3 { font-size: 1.1rem; font-weight: 500; }
        .modal-close { background: none; border: none; color: var(--text-secondary); cursor: pointer; padding: 4px; }
        .modal-close:hover { color: var(--text-primary); }
        .modal-body { padding: 20px; overflow-y: auto; flex: 1; }
        .markdown-content { line-height: 1.6; }
        .markdown-content h1 { font-size: 1.5rem; margin: 20px 0 12px; }
        .markdown-content h2 { font-size: 1.25rem; margin: 18px 0 10px; border-bottom: 1px solid var(--border); padding-bottom: 8px; }
        .markdown-content h3 { font-size: 1.1rem; margin: 16px 0 8px; }
        .markdown-content p { margin: 12px 0; }
        .markdown-content code { background: var(--bg-primary); padding: 2px 6px; border-radius: 4px; font-size: 0.85em; }
        .markdown-content pre { background: var(--bg-primary); padding: 16px; border-radius: 6px; overflow-x: auto; margin: 12px 0; }
        .markdown-content pre code { padding: 0; background: none; }
        .markdown-content ul, .markdown-content ol { margin: 12px 0; padding-left: 24px; }
        .markdown-content li { margin: 6px 0; }
        .markdown-content table { width: 100%; margin: 16px 0; border-collapse: collapse; }
        .markdown-content table th, .markdown-content table td { border: 1px solid var(--border); padding: 8px 12px; }
        .markdown-content blockquote { border-left: 3px solid var(--accent); padding-left: 16px; margin: 12px 0; color: var(--text-secondary); }
        .detail-panel { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: 8px; overflow: hidden; }
        .detail-header { padding: 16px 20px; border-bottom: 1px solid var(--border); display: flex; align-items: center; gap: 12px; }
        .detail-header h3 { font-size: 1.1rem; font-weight: 500; }
        .detail-body { padding: 20px; }
        .list-item { padding: 16px 20px; border-bottom: 1px solid var(--border); display: flex; justify-content: space-between; align-items: center; cursor: pointer; transition: background 0.15s; }
        .list-item:hover { background: var(--bg-tertiary); }
        .list-item:last-child { border-bottom: none; }
        .list-item-content h4 { font-weight: 500; margin-bottom: 4px; }
        .list-item-content p { font-size: 0.8rem; color: var(--text-secondary); }
        .two-col { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; }
        @media (max-width: 1000px) { .two-col { grid-template-columns: 1fr; } }
        .hour-chart { display: flex; gap: 4px; align-items: flex-end; height: 100px; }
        .hour-bar { flex: 1; background: var(--accent); border-radius: 2px 2px 0 0; min-height: 4px; transition: opacity 0.15s; }
        .hour-bar:hover { opacity: 0.8; }
        .token-stat { margin: 8px 0; }
        .token-stat .label { font-size: 0.85rem; color: var(--text-secondary); }
        .token-stat .value { font-size: 1.2rem; font-weight: 500; }
        .token-stat.input .value { color: var(--info); }
        .token-stat.output .value { color: var(--success); }
        .token-stat.cache .value { color: var(--text-secondary); }
        .todo-item { display: flex; align-items: flex-start; gap: 12px; padding: 12px; border-radius: 6px; margin-bottom: 8px; background: var(--bg-tertiary); }
        .todo-checkbox { width: 18px; height: 18px; border-radius: 4px; border: 2px solid var(--border); flex-shrink: 0; margin-top: 2px; }
        .todo-item.completed .todo-checkbox { background: var(--success); border-color: var(--success); }
        .todo-item.completed .todo-content { text-decoration: line-through; opacity: 0.6; }
        .empty-state { text-align: center; padding: 40px; color: var(--text-secondary); }
        ::-webkit-scrollbar { width: 8px; height: 8px; }
        ::-webkit-scrollbar-track { background: var(--bg-primary); }
        ::-webkit-scrollbar-thumb { background: var(--border); border-radius: 4px; }
        ::-webkit-scrollbar-thumb:hover { background: var(--text-secondary); }
    </style>
</head>
<body>
    <div class="container">
        <nav class="sidebar">
            <div class="logo">
                <h1>
                    <svg viewBox="0 0 24 24" width="28" height="28" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z"/></svg>
                    Claude Explorer
                </h1>
                <span>~/.claude Deep Dive</span>
            </div>
            <div class="nav-section">
                <div class="nav-section-title">Overview</div>
                <div class="nav-item active" data-page="dashboard">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/></svg>
                    Dashboard
                </div>
            </div>
            <div class="nav-section">
                <div class="nav-section-title">Sessions</div>
                <div class="nav-item" data-page="history">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
                    History <span class="count" id="historyCount">0</span>
                </div>
                <div class="nav-item" data-page="projects">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 19a2 2 0 01-2 2H4a2 2 0 01-2-2V5a2 2 0 012-2h5l2 3h9a2 2 0 012 2z"/></svg>
                    Projects <span class="count" id="projectsCount">0</span>
                </div>
                <div class="nav-item" data-page="fileHistory">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 20h9M16.5 3.5a2.12 2.12 0 013 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>
                    File History <span class="count" id="fileHistoryCount">0</span>
                </div>
            </div>
            <div class="nav-section">
                <div class="nav-section-title">Content</div>
                <div class="nav-item" data-page="plans">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
                    Plans <span class="count" id="plansCount">0</span>
                </div>
                <div class="nav-item" data-page="todos">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11"/></svg>
                    Todos <span class="count" id="todosCount">0</span>
                </div>
            </div>
            <div class="nav-section">
                <div class="nav-section-title">Config</div>
                <div class="nav-item" data-page="settings">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-2 2 2 2 0 01-2-2v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83 0 2 2 0 010-2.83l.06-.06a1.65 1.65 0 00.33-1.82 1.65 1.65 0 00-1.51-1H3a2 2 0 01-2-2 2 2 0 012-2h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 010-2.83 2 2 0 012.83 0l.06.06a1.65 1.65 0 001.82.33H9a1.65 1.65 0 001-1.51V3a2 2 0 012-2 2 2 0 012 2v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 0 2 2 0 010 2.83l-.06.06a1.65 1.65 0 00-.33 1.82V9a1.65 1.65 0 001.51 1H21a2 2 0 012 2 2 2 0 01-2 2h-.09a1.65 1.65 0 00-1.51 1z"/></svg>
                    Settings
                </div>
                <div class="nav-item" data-page="plugins">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"/></svg>
                    Plugins
                </div>
                <div class="nav-item" data-page="skills">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>
                    Skills <span class="count" id="skillsCount">0</span>
                </div>
            </div>
        </nav>
        <main class="main" id="mainContent"></main>
    </div>
    <div class="modal-overlay" id="modal">
        <div class="modal">
            <div class="modal-header">
                <h3 id="modalTitle">Details</h3>
                <button class="modal-close" onclick="closeModal()">
                    <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                </button>
            </div>
            <div class="modal-body" id="modalBody"></div>
        </div>
    </div>
    <script>
        const data = EMBEDDED_DATA_PLACEHOLDER;

        function formatNumber(n) { return n >= 1e6 ? (n/1e6).toFixed(1)+'M' : n >= 1e3 ? (n/1e3).toFixed(1)+'K' : n.toString(); }
        function formatBytes(b) { return b >= 1048576 ? (b/1048576).toFixed(1)+' MB' : b >= 1024 ? (b/1024).toFixed(1)+' KB' : b+' B'; }
        function formatDuration(ms) { return Math.floor(ms/3600000)+'h '+Math.floor((ms%3600000)/60000)+'m'; }
        function formatDate(ts) { return new Date(ts).toLocaleString(); }
        function pathToName(p) { return p.replace(/-/g, '/').replace(/^\//, ''); }
        function escapeHtml(t) { const d = document.createElement('div'); d.textContent = t; return d.innerHTML; }

        document.getElementById('historyCount').textContent = data.history?.length || 0;
        document.getElementById('projectsCount').textContent = data.projects?.length || 0;
        document.getElementById('plansCount').textContent = data.plans?.length || 0;
        document.getElementById('skillsCount').textContent = data.skills?.length || 0;
        document.getElementById('todosCount').textContent = data.todos?.length || 0;
        document.getElementById('fileHistoryCount').textContent = data.fileHistory?.length || 0;

        function buildDashboard() {
            const s = data.stats || {}, u = s.modelUsage?.["claude-opus-4-5-20251101"] || {};
            return `<div class="page-header"><h2>Dashboard</h2><p>Claude Code usage overview</p></div>
                <div class="stats-grid">
                    <div class="stat-card"><div class="label">Total Sessions</div><div class="value">${s.totalSessions||0}</div><div class="subtitle">Since ${s.firstSessionDate?new Date(s.firstSessionDate).toLocaleDateString():'N/A'}</div></div>
                    <div class="stat-card"><div class="label">Total Messages</div><div class="value">${formatNumber(s.totalMessages||0)}</div></div>
                    <div class="stat-card"><div class="label">Longest Session</div><div class="value">${s.longestSession?formatDuration(s.longestSession.duration):'N/A'}</div><div class="subtitle">${s.longestSession?.messageCount||0} messages</div></div>
                    <div class="stat-card"><div class="label">History Entries</div><div class="value">${data.history?.length||0}</div></div>
                    <div class="stat-card"><div class="label">Projects</div><div class="value">${data.projects?.length||0}</div></div>
                    <div class="stat-card"><div class="label">Plans</div><div class="value">${data.plans?.length||0}</div></div>
                </div>
                <div class="chart-container"><h3>Activity Over Time</h3><div class="chart-wrapper"><canvas id="activityChart"></canvas></div></div>
                <div class="two-col">
                    <div class="chart-container"><h3>Usage by Hour</h3><div class="hour-chart" id="hourChart"></div></div>
                    <div class="chart-container"><h3>Token Usage</h3>
                        <div class="token-stat input"><div class="label">Input</div><div class="value">${formatNumber(u.inputTokens||0)}</div></div>
                        <div class="token-stat output"><div class="label">Output</div><div class="value">${formatNumber(u.outputTokens||0)}</div></div>
                        <div class="token-stat cache"><div class="label">Cache Read</div><div class="value">${formatNumber(u.cacheReadInputTokens||0)}</div></div>
                    </div>
                </div>`;
        }

        function buildHistory() {
            const h = data.history || [], projs = [...new Set(h.map(x=>x.project?.split('/').pop()).filter(Boolean))];
            return `<div class="page-header"><h2>History</h2><p>${h.length} entries</p></div>
                <div class="search-box"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg><input type="text" placeholder="Search..." id="historySearch" oninput="filterHistory()"></div>
                <div class="filters"><button class="filter-btn active" data-filter="all" onclick="filterHistoryByProject('all')">All</button>${projs.map(p=>`<button class="filter-btn" data-filter="${p}" onclick="filterHistoryByProject('${p}')">${p}</button>`).join('')}</div>
                <div class="table-container"><div class="table-scroll"><table><thead><tr><th>Message</th><th>Project</th><th>Session</th><th>Time</th></tr></thead>
                <tbody id="historyTableBody">${h.slice(0,200).map((x,i)=>`<tr class="clickable history-row" data-index="${i}" data-project="${x.project?.split('/').pop()||''}" onclick="showHistoryDetail(${i})"><td>${escapeHtml((x.display||'').substring(0,80))}${(x.display||'').length>80?'...':''}</td><td><span class="badge badge-accent">${x.project?.split('/').pop()||'N/A'}</span></td><td style="font-family:monospace;font-size:0.75rem;color:var(--text-secondary)">${(x.sessionId||'').substring(0,8)}...</td><td style="color:var(--text-secondary);white-space:nowrap">${x.timestamp?formatDate(x.timestamp):'N/A'}</td></tr>`).join('')}</tbody></table></div></div>`;
        }

        function buildProjects() {
            return `<div class="page-header"><h2>Projects</h2><p>${data.projects?.length||0} projects</p></div>
                <div class="card-grid">${(data.projects||[]).map(p=>`<div class="card" onclick="showProjectSessions('${p.path}')"><div class="card-title"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 19a2 2 0 01-2 2H4a2 2 0 01-2-2V5a2 2 0 012-2h5l2 3h9a2 2 0 012 2z"/></svg>${pathToName(p.path).split('/').pop()}</div><div class="card-meta">${pathToName(p.path)}</div><div class="card-content"><span class="badge badge-info">${p.sessionCount} sessions</span></div></div>`).join('')}</div>`;
        }

        function buildFileHistory() {
            return `<div class="page-header"><h2>File History</h2><p>${data.fileHistory?.length||0} sessions</p></div>
                <div class="card-grid">${(data.fileHistory||[]).map(f=>`<div class="card" onclick="showFileHistoryDetail('${f.sessionId}')"><div class="card-title"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 20h9M16.5 3.5a2.12 2.12 0 013 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>Session ${f.sessionId.substring(0,8)}...</div><div class="card-meta">${f.fileCount} files</div><div class="card-content">${f.files.slice(0,3).map(x=>`<div style="font-size:0.75rem;color:var(--text-secondary)">${x.name} (${formatBytes(x.size)})</div>`).join('')}${f.files.length>3?`<div style="font-size:0.75rem;color:var(--text-secondary)">+${f.files.length-3} more</div>`:''}</div></div>`).join('')}</div>`;
        }

        function buildPlans() {
            return `<div class="page-header"><h2>Plans</h2><p>${data.plans?.length||0} plans</p></div>
                <div class="card-grid">${(data.plans||[]).map((p,i)=>`<div class="card" onclick="showPlanDetail(${i})"><div class="card-title"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>${p.name}</div><div class="card-meta">${formatBytes(p.size)} • ${p.modified}</div><div class="card-content">${(p.content||'').substring(0,150)}...</div></div>`).join('')}</div>`;
        }

        function buildTodos() {
            const t = data.todos || [];
            if (!t.length) return `<div class="page-header"><h2>Todos</h2></div><div class="empty-state">No todos</div>`;
            return `<div class="page-header"><h2>Todos</h2><p>${t.length} lists</p></div>${t.map(todo=>`<div class="detail-panel" style="margin-bottom:16px"><div class="detail-header"><h3>Session ${todo.id.substring(0,8)}...</h3><span class="badge badge-info">${Array.isArray(todo.tasks)?todo.tasks.length:0} tasks</span></div><div class="detail-body">${Array.isArray(todo.tasks)?todo.tasks.map(task=>`<div class="todo-item ${task.status==='completed'?'completed':''}"><div class="todo-checkbox"></div><div class="todo-content"><div>${escapeHtml(task.content||'')}</div><div style="font-size:0.75rem;color:var(--text-secondary);margin-top:4px"><span class="badge ${task.status==='completed'?'badge-success':'badge-warning'}">${task.status||'pending'}</span></div></div></div>`).join(''):'<div class="empty-state">No tasks</div>'}</div></div>`).join('')}`;
        }

        function buildSettings() {
            return `<div class="page-header"><h2>Settings</h2></div>
                <div class="detail-panel" style="margin-bottom:24px"><div class="detail-header"><h3>settings.json</h3></div><div class="detail-body"><div class="code-block">${JSON.stringify(data.settings||{},null,2)}</div></div></div>
                <div class="detail-panel"><div class="detail-header"><h3>settings.local.json</h3></div><div class="detail-body"><div class="code-block">${JSON.stringify(data.settingsLocal||{},null,2)}</div></div></div>`;
        }

        function buildPlugins() {
            const p = data.installedPlugins?.plugins || {}, m = data.marketplaces || {};
            return `<div class="page-header"><h2>Plugins</h2></div>
                <div class="detail-panel" style="margin-bottom:24px"><div class="detail-header"><h3>Installed</h3></div>${Object.entries(p).map(([n,v])=>`<div class="list-item"><div class="list-item-content"><h4>${n}</h4><p>v${v[0]?.version||'?'}</p></div><span class="badge badge-success">Installed</span></div>`).join('')||'<div class="empty-state">None</div>'}</div>
                <div class="detail-panel"><div class="detail-header"><h3>Marketplaces</h3></div>${Object.entries(m).map(([n,i])=>`<div class="list-item"><div class="list-item-content"><h4>${n}</h4><p>${i.source?.repo||i.installLocation}</p></div><span class="badge badge-accent">Active</span></div>`).join('')||'<div class="empty-state">None</div>'}</div>`;
        }

        function buildSkills() {
            return `<div class="page-header"><h2>Skills</h2><p>${data.skills?.length||0} skills</p></div>
                <div class="card-grid">${(data.skills||[]).map((s,i)=>`<div class="card" onclick="showSkillDetail(${i})"><div class="card-title"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>${s.name}</div><div class="card-meta">Files: ${s.files?.join(', ')||'N/A'}</div><div class="card-content">${s.content?s.content.substring(0,150)+'...':'No SKILL.md'}</div></div>`).join('')||'<div class="empty-state">No skills</div>'}</div>`;
        }

        function buildPages() {
            document.getElementById('mainContent').innerHTML = `
                <div class="page active" id="dashboard">${buildDashboard()}</div>
                <div class="page" id="history">${buildHistory()}</div>
                <div class="page" id="projects">${buildProjects()}</div>
                <div class="page" id="fileHistory">${buildFileHistory()}</div>
                <div class="page" id="plans">${buildPlans()}</div>
                <div class="page" id="todos">${buildTodos()}</div>
                <div class="page" id="settings">${buildSettings()}</div>
                <div class="page" id="plugins">${buildPlugins()}</div>
                <div class="page" id="skills">${buildSkills()}</div>`;
            initCharts();
        }

        function initCharts() {
            const s = data.stats || {};
            const ctx = document.getElementById('activityChart')?.getContext('2d');
            if (ctx && s.dailyActivity) {
                new Chart(ctx, {
                    type: 'line',
                    data: {
                        labels: s.dailyActivity.map(d => new Date(d.date).toLocaleDateString('en-US', {month:'short',day:'numeric'})),
                        datasets: [{label:'Messages',data:s.dailyActivity.map(d=>d.messageCount),borderColor:'#c9885a',backgroundColor:'rgba(201,136,90,0.1)',fill:true,tension:0.4},{label:'Tool Calls',data:s.dailyActivity.map(d=>d.toolCallCount),borderColor:'#3fb950',backgroundColor:'rgba(63,185,80,0.1)',fill:true,tension:0.4}]
                    },
                    options: {responsive:true,maintainAspectRatio:false,plugins:{legend:{labels:{color:'#8b949e'}}},scales:{x:{grid:{color:'#30363d'},ticks:{color:'#8b949e'}},y:{grid:{color:'#30363d'},ticks:{color:'#8b949e'}}}}
                });
            }
            const hc = document.getElementById('hourChart');
            if (hc && s.hourCounts) {
                const max = Math.max(...Object.values(s.hourCounts));
                for (let h=0;h<24;h++) { const c=s.hourCounts[h]||0; const bar=document.createElement('div'); bar.className='hour-bar'; bar.style.height=(c>0?(c/max)*100:4)+'%'; bar.title=h+':00 - '+c+' sessions'; hc.appendChild(bar); }
            }
        }

        document.querySelectorAll('.nav-item').forEach(item => {
            item.addEventListener('click', () => {
                document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
                item.classList.add('active');
                document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
                document.getElementById(item.dataset.page)?.classList.add('active');
            });
        });

        function filterHistory() { const q=document.getElementById('historySearch').value.toLowerCase(); document.querySelectorAll('.history-row').forEach(r=>{r.style.display=r.textContent.toLowerCase().includes(q)?'':'none';}); }
        function filterHistoryByProject(p) { document.querySelectorAll('.filters .filter-btn').forEach(b=>b.classList.remove('active')); document.querySelector(`.filters .filter-btn[data-filter="${p}"]`)?.classList.add('active'); document.querySelectorAll('.history-row').forEach(r=>{r.style.display=p==='all'||r.dataset.project===p?'':'none';}); }

        function showModal(t,c) { document.getElementById('modalTitle').textContent=t; document.getElementById('modalBody').innerHTML=c; document.getElementById('modal').classList.add('active'); }
        function closeModal() { document.getElementById('modal').classList.remove('active'); }
        document.getElementById('modal').addEventListener('click',e=>{if(e.target.id==='modal')closeModal();});
        document.addEventListener('keydown',e=>{if(e.key==='Escape')closeModal();});

        function showHistoryDetail(i) { const h=data.history[i]; showModal('Message',`<div class="detail-panel"><div class="detail-body"><div style="margin-bottom:16px"><div style="font-size:0.8rem;color:var(--text-secondary);margin-bottom:8px">Message</div><div class="code-block">${escapeHtml(h.display||'')}</div></div><div style="display:grid;grid-template-columns:1fr 1fr;gap:16px"><div><div style="font-size:0.8rem;color:var(--text-secondary)">Project</div><div>${h.project||'N/A'}</div></div><div><div style="font-size:0.8rem;color:var(--text-secondary)">Session</div><div style="font-family:monospace">${h.sessionId||'N/A'}</div></div><div><div style="font-size:0.8rem;color:var(--text-secondary)">Time</div><div>${h.timestamp?formatDate(h.timestamp):'N/A'}</div></div></div></div></div>`); }
        function showProjectSessions(path) { const p=data.projects.find(x=>x.path===path); if(!p)return; showModal(pathToName(path).split('/').pop(),`<div class="table-container"><div class="table-scroll" style="max-height:500px"><table><thead><tr><th>Session ID</th><th>Size</th><th>Lines</th></tr></thead><tbody>${p.sessions.map(s=>`<tr><td style="font-family:monospace">${s.id}</td><td>${formatBytes(s.size)}</td><td>${formatNumber(s.lines)}</td></tr>`).join('')}</tbody></table></div></div><p style="margin-top:16px;font-size:0.85rem;color:var(--text-secondary)">Files in ~/.claude/projects/${path}/</p>`); }
        function showFileHistoryDetail(id) { const f=data.fileHistory.find(x=>x.sessionId===id); if(!f)return; showModal('File History: '+id.substring(0,8)+'...',`<p style="margin-bottom:16px;color:var(--text-secondary)">${f.fileCount} files</p><div class="table-container"><div class="table-scroll" style="max-height:500px"><table><thead><tr><th>File</th><th>Size</th></tr></thead><tbody>${f.files.map(x=>`<tr><td style="font-family:monospace;font-size:0.85rem">${x.name}</td><td>${formatBytes(x.size)}</td></tr>`).join('')}</tbody></table></div></div><p style="margin-top:16px;font-size:0.85rem;color:var(--text-secondary)">Files in ~/.claude/file-history/${id}/</p>`); }
        function showPlanDetail(i) { const p=data.plans[i]; if(!p)return; showModal(p.name,`<div class="markdown-content">${typeof marked!=='undefined'?marked.parse(p.content||''):`<pre>${escapeHtml(p.content||'')}</pre>`}</div>`); }
        function showSkillDetail(i) { const s=data.skills[i]; if(!s)return; const html=s.content?(typeof marked!=='undefined'?marked.parse(s.content):`<pre>${escapeHtml(s.content)}</pre>`):'<p style="color:var(--text-secondary)">No SKILL.md</p>'; showModal(s.name,`<div style="margin-bottom:16px"><div style="font-size:0.8rem;color:var(--text-secondary);margin-bottom:8px">Files</div><div class="code-block">${s.files?.join('\n')||'None'}</div></div><div style="font-size:0.8rem;color:var(--text-secondary);margin-bottom:8px">SKILL.md</div><div class="markdown-content">${html}</div>`); }

        buildPages();
    </script>
</body>
</html>
HTMLEOF

# Replace placeholder with actual data
python3 -c "
import sys
data = sys.argv[1]
with open('$OUTPUT_FILE', 'r') as f:
    content = f.read()
content = content.replace('EMBEDDED_DATA_PLACEHOLDER', data)
with open('$OUTPUT_FILE', 'w') as f:
    f.write(content)
" "$DATA"

echo "Built: $OUTPUT_FILE"
echo "Open with: open $OUTPUT_FILE"
