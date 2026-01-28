#!/usr/bin/env python3
"""
Claude Explorer - Interactive viewer for ~/.claude data

A command-line tool that generates an interactive HTML dashboard
to explore your Claude Code session history, settings, plans, and more.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

VERSION = "1.0.0"

def get_default_claude_dir():
    """Get the default Claude directory based on platform."""
    return Path.home() / ".claude"

def get_default_output():
    """Get default output path."""
    return Path.home() / "claude-explorer.html"

def safe_read_json(path):
    """Safely read a JSON file, returning empty dict on failure."""
    try:
        with open(path) as f:
            return json.load(f)
    except:
        return {}

def safe_read_jsonl(path):
    """Safely read a JSONL file, returning list of items."""
    items = []
    try:
        with open(path) as f:
            for line in f:
                try:
                    items.append(json.loads(line.strip()))
                except:
                    pass
    except:
        pass
    return items

def extract_message_content(msg):
    """Extract readable content from a message object."""
    content = msg.get('content', '')
    if isinstance(content, str):
        return content
    elif isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                if item.get('type') == 'text':
                    parts.append(item.get('text', ''))
                elif item.get('type') == 'tool_use':
                    parts.append('[Tool: ' + item.get('name', 'unknown') + ']')
        return '\n'.join(parts)
    return str(content)

def parse_session(path, max_messages=500, max_content_length=5000):
    """Parse a session JSONL file into messages."""
    messages = []
    raw = safe_read_jsonl(path)
    for item in raw:
        msg_type = item.get('type')
        if msg_type not in ['user', 'assistant']:
            continue
        msg = item.get('message', {})
        role = msg.get('role', msg_type)
        content = extract_message_content(msg)
        timestamp = item.get('timestamp', '')
        uuid = item.get('uuid', '')
        if content.strip():
            messages.append({
                'role': role,
                'content': content[:max_content_length],
                'timestamp': timestamp,
                'uuid': uuid[:8] if uuid else ''
            })
        if len(messages) >= max_messages:
            break
    return messages

def extract_data(claude_dir, max_sessions=20, max_messages=500, verbose=False):
    """Extract all data from the Claude directory."""
    claude_dir = Path(claude_dir)

    if not claude_dir.exists():
        print(f"Error: Claude directory not found: {claude_dir}", file=sys.stderr)
        print("Make sure you have Claude Code installed and have run it at least once.", file=sys.stderr)
        sys.exit(1)

    if verbose:
        print(f"Reading from: {claude_dir}")

    data = {}

    # Basic settings
    data['settings'] = safe_read_json(claude_dir / 'settings.json')
    data['settingsLocal'] = safe_read_json(claude_dir / 'settings.local.json')
    data['stats'] = safe_read_json(claude_dir / 'stats-cache.json')
    data['installedPlugins'] = safe_read_json(claude_dir / 'plugins' / 'installed_plugins.json')
    data['marketplaces'] = safe_read_json(claude_dir / 'plugins' / 'known_marketplaces.json')

    # History
    data['history'] = safe_read_jsonl(claude_dir / 'history.jsonl')
    if verbose:
        print(f"  Found {len(data['history'])} history entries")

    # Plans with content
    plans = []
    plans_dir = claude_dir / 'plans'
    if plans_dir.exists():
        for f in sorted(plans_dir.glob('*.md')):
            try:
                plans.append({
                    'name': f.stem,
                    'file': f.name,
                    'size': f.stat().st_size,
                    'modified': datetime.fromtimestamp(f.stat().st_mtime).strftime('%Y-%m-%d'),
                    'content': f.read_text()
                })
            except:
                pass
    data['plans'] = plans
    if verbose:
        print(f"  Found {len(plans)} plans")

    # Skills
    skills = []
    skills_dir = claude_dir / 'skills'
    if skills_dir.exists():
        for d in skills_dir.iterdir():
            if d.is_dir():
                skill = {'name': d.name, 'files': [f.name for f in d.iterdir()], 'content': ''}
                skill_md = d / 'SKILL.md'
                if skill_md.exists():
                    try:
                        skill['content'] = skill_md.read_text()
                    except:
                        pass
                skills.append(skill)
    data['skills'] = skills
    if verbose:
        print(f"  Found {len(skills)} skills")

    # Todos
    todos = []
    todos_dir = claude_dir / 'todos'
    if todos_dir.exists():
        for f in todos_dir.glob('*.json'):
            try:
                content = json.loads(f.read_text())
                if content and content != []:
                    todos.append({'id': f.stem, 'tasks': content})
            except:
                pass
    data['todos'] = todos
    if verbose:
        print(f"  Found {len(todos)} todo lists")

    # File history
    file_history = []
    fh_dir = claude_dir / 'file-history'
    if fh_dir.exists():
        for d in fh_dir.iterdir():
            if d.is_dir():
                files = [{'name': f.name, 'size': f.stat().st_size} for f in d.iterdir() if f.is_file()][:50]
                file_history.append({'sessionId': d.name, 'fileCount': len(files), 'files': files})
    data['fileHistory'] = file_history

    # Projects with session content
    projects = []
    projects_dir = claude_dir / 'projects'
    if projects_dir.exists():
        for d in projects_dir.iterdir():
            if d.is_dir() and not d.name.startswith('.'):
                sessions = []
                session_files = sorted(d.glob('*.jsonl'), key=lambda x: x.stat().st_mtime, reverse=True)
                for f in session_files[:max_sessions]:
                    try:
                        messages = parse_session(f, max_messages=max_messages)
                        sessions.append({
                            'id': f.stem,
                            'size': f.stat().st_size,
                            'lines': sum(1 for _ in open(f)),
                            'messageCount': len(messages),
                            'messages': messages,
                            'firstTimestamp': messages[0].get('timestamp', '') if messages else '',
                            'lastTimestamp': messages[-1].get('timestamp', '') if messages else '',
                            'preview': messages[0]['content'][:200] if messages else ''
                        })
                    except:
                        pass
                if sessions:
                    projects.append({
                        'path': d.name,
                        'sessionCount': len(sessions),
                        'sessions': sessions
                    })
    data['projects'] = projects
    if verbose:
        total_sessions = sum(p['sessionCount'] for p in projects)
        print(f"  Found {len(projects)} projects with {total_sessions} sessions")

    return data

def get_html_template():
    """Return the HTML template for the explorer."""
    return '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Claude Explorer</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
    <style>
        :root {
            --bg-primary: #0d1117; --bg-secondary: #161b22; --bg-tertiary: #21262d;
            --border: #30363d; --text-primary: #e6edf3; --text-secondary: #8b949e;
            --accent: #c9885a; --success: #3fb950; --warning: #d29922; --info: #58a6ff;
            --user-bg: #1c2128; --assistant-bg: #161b22;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: var(--bg-primary); color: var(--text-primary); min-height: 100vh; }
        .container { display: flex; min-height: 100vh; }
        .sidebar { width: 260px; background: var(--bg-secondary); border-right: 1px solid var(--border); padding: 20px 0; flex-shrink: 0; display: flex; flex-direction: column; overflow-y: auto; }
        .logo { padding: 0 20px 20px; border-bottom: 1px solid var(--border); margin-bottom: 20px; }
        .logo h1 { font-size: 1.4rem; font-weight: 600; color: var(--accent); }
        .logo span { font-size: 0.75rem; color: var(--text-secondary); }
        .nav-section { padding: 0 12px; margin-bottom: 20px; }
        .nav-section-title { font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.05em; color: var(--text-secondary); padding: 0 8px; margin-bottom: 8px; }
        .nav-item { display: flex; align-items: center; gap: 10px; padding: 8px 12px; border-radius: 6px; cursor: pointer; color: var(--text-secondary); transition: all 0.15s; font-size: 0.85rem; }
        .nav-item:hover { background: var(--bg-tertiary); color: var(--text-primary); }
        .nav-item.active { background: var(--accent); color: white; }
        .nav-item svg { width: 16px; height: 16px; flex-shrink: 0; }
        .nav-item .count { margin-left: auto; background: var(--bg-tertiary); padding: 2px 6px; border-radius: 10px; font-size: 0.65rem; }
        .nav-item.active .count { background: rgba(255,255,255,0.2); }
        .main { flex: 1; display: flex; flex-direction: column; overflow: hidden; }
        .main-header { padding: 20px 24px; border-bottom: 1px solid var(--border); flex-shrink: 0; }
        .main-header h2 { font-size: 1.3rem; margin-bottom: 4px; }
        .main-header p { color: var(--text-secondary); font-size: 0.85rem; }
        .main-content { flex: 1; overflow-y: auto; padding: 24px; }
        .breadcrumb { display: flex; align-items: center; gap: 8px; margin-bottom: 8px; font-size: 0.85rem; }
        .breadcrumb a { color: var(--accent); cursor: pointer; }
        .breadcrumb a:hover { text-decoration: underline; }
        .breadcrumb span { color: var(--text-secondary); }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; margin-bottom: 20px; }
        .stat-card { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: 8px; padding: 16px; }
        .stat-card .label { font-size: 0.75rem; color: var(--text-secondary); margin-bottom: 4px; }
        .stat-card .value { font-size: 1.5rem; font-weight: 600; color: var(--accent); }
        .stat-card .subtitle { font-size: 0.7rem; color: var(--text-secondary); margin-top: 2px; }
        .card-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 12px; }
        .card { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: 8px; padding: 16px; cursor: pointer; transition: all 0.15s; }
        .card:hover { border-color: var(--accent); transform: translateY(-1px); }
        .card-title { font-weight: 500; margin-bottom: 6px; display: flex; align-items: center; gap: 8px; font-size: 0.95rem; }
        .card-meta { font-size: 0.75rem; color: var(--text-secondary); word-break: break-all; }
        .card-content { margin-top: 10px; font-size: 0.8rem; color: var(--text-secondary); line-height: 1.4; }
        .session-list { display: flex; flex-direction: column; gap: 8px; }
        .session-item { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: 8px; padding: 14px 16px; cursor: pointer; transition: all 0.15s; }
        .session-item:hover { border-color: var(--accent); }
        .session-item-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; }
        .session-item-title { font-weight: 500; font-size: 0.9rem; }
        .session-item-meta { font-size: 0.75rem; color: var(--text-secondary); }
        .session-item-preview { font-size: 0.8rem; color: var(--text-secondary); line-height: 1.4; overflow: hidden; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; }
        .conversation { display: flex; flex-direction: column; gap: 1px; }
        .message { padding: 16px 20px; }
        .message.user { background: var(--user-bg); border-left: 3px solid var(--accent); }
        .message.assistant { background: var(--assistant-bg); border-left: 3px solid var(--info); }
        .message-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }
        .message-role { font-size: 0.75rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; }
        .message.user .message-role { color: var(--accent); }
        .message.assistant .message-role { color: var(--info); }
        .message-time { font-size: 0.7rem; color: var(--text-secondary); }
        .message-content { font-size: 0.9rem; line-height: 1.6; white-space: pre-wrap; word-break: break-word; }
        .message-content code { background: var(--bg-primary); padding: 2px 6px; border-radius: 4px; font-size: 0.85em; }
        .tool-call { background: var(--bg-tertiary); border-radius: 4px; padding: 8px 12px; margin: 8px 0; font-size: 0.8rem; font-family: monospace; color: var(--text-secondary); }
        .table-container { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: 8px; overflow: hidden; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 10px 16px; text-align: left; border-bottom: 1px solid var(--border); }
        th { font-size: 0.7rem; text-transform: uppercase; color: var(--text-secondary); font-weight: 500; background: var(--bg-secondary); position: sticky; top: 0; }
        td { font-size: 0.85rem; }
        tr:hover { background: var(--bg-tertiary); }
        tr:last-child td { border-bottom: none; }
        .table-scroll { max-height: 500px; overflow-y: auto; }
        .chart-container { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: 8px; padding: 16px; margin-bottom: 16px; }
        .chart-container h3 { font-size: 0.9rem; margin-bottom: 12px; }
        .chart-wrapper { height: 250px; }
        .two-col { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
        @media (max-width: 900px) { .two-col { grid-template-columns: 1fr; } }
        .hour-chart { display: flex; gap: 3px; align-items: flex-end; height: 80px; }
        .hour-bar { flex: 1; background: var(--accent); border-radius: 2px 2px 0 0; min-height: 3px; }
        .token-stat { margin: 6px 0; }
        .token-stat .label { font-size: 0.8rem; color: var(--text-secondary); }
        .token-stat .value { font-size: 1.1rem; font-weight: 500; }
        .token-stat.input .value { color: var(--info); }
        .token-stat.output .value { color: var(--success); }
        .token-stat.cache .value { color: var(--text-secondary); }
        .badge { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 0.65rem; font-weight: 500; }
        .badge-success { background: rgba(63, 185, 80, 0.2); color: var(--success); }
        .badge-warning { background: rgba(210, 153, 34, 0.2); color: var(--warning); }
        .badge-accent { background: rgba(201, 136, 90, 0.2); color: var(--accent); }
        .badge-info { background: rgba(88, 166, 255, 0.2); color: var(--info); }
        .code-block { background: var(--bg-primary); border: 1px solid var(--border); border-radius: 6px; padding: 12px; font-family: 'Monaco', monospace; font-size: 0.8rem; overflow-x: auto; white-space: pre-wrap; word-break: break-word; }
        .search-box { display: flex; align-items: center; gap: 8px; background: var(--bg-tertiary); border: 1px solid var(--border); border-radius: 6px; padding: 8px 12px; margin-bottom: 12px; }
        .search-box input { flex: 1; background: none; border: none; color: var(--text-primary); font-size: 0.85rem; outline: none; }
        .search-box svg { color: var(--text-secondary); width: 14px; height: 14px; }
        .filters { display: flex; gap: 6px; margin-bottom: 12px; flex-wrap: wrap; }
        .filter-btn { padding: 5px 10px; background: var(--bg-tertiary); border: 1px solid var(--border); border-radius: 6px; color: var(--text-secondary); font-size: 0.75rem; cursor: pointer; transition: all 0.15s; }
        .filter-btn:hover, .filter-btn.active { background: var(--accent); color: white; border-color: var(--accent); }
        .modal-overlay { display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.7); z-index: 1000; align-items: center; justify-content: center; }
        .modal-overlay.active { display: flex; }
        .modal { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: 12px; max-width: 900px; max-height: 85vh; width: 95%; overflow: hidden; display: flex; flex-direction: column; }
        .modal-header { padding: 16px 20px; border-bottom: 1px solid var(--border); display: flex; justify-content: space-between; align-items: center; }
        .modal-header h3 { font-size: 1rem; }
        .modal-close { background: none; border: none; color: var(--text-secondary); cursor: pointer; padding: 4px; }
        .modal-close:hover { color: var(--text-primary); }
        .modal-body { flex: 1; overflow-y: auto; }
        .markdown-content { padding: 20px; line-height: 1.6; }
        .markdown-content h1 { font-size: 1.4rem; margin: 16px 0 10px; }
        .markdown-content h2 { font-size: 1.2rem; margin: 14px 0 8px; border-bottom: 1px solid var(--border); padding-bottom: 6px; }
        .markdown-content h3 { font-size: 1rem; margin: 12px 0 6px; }
        .markdown-content p { margin: 10px 0; }
        .markdown-content pre { background: var(--bg-primary); padding: 12px; border-radius: 6px; overflow-x: auto; margin: 10px 0; }
        .markdown-content code { background: var(--bg-primary); padding: 2px 6px; border-radius: 4px; font-size: 0.85em; }
        .markdown-content pre code { padding: 0; background: none; }
        .markdown-content ul, .markdown-content ol { margin: 10px 0; padding-left: 20px; }
        .markdown-content table { width: 100%; margin: 12px 0; border-collapse: collapse; }
        .markdown-content th, .markdown-content td { border: 1px solid var(--border); padding: 6px 10px; }
        .markdown-content blockquote { border-left: 3px solid var(--accent); padding-left: 12px; margin: 10px 0; color: var(--text-secondary); }
        .detail-panel { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: 8px; overflow: hidden; margin-bottom: 16px; }
        .detail-header { padding: 12px 16px; border-bottom: 1px solid var(--border); display: flex; align-items: center; gap: 10px; }
        .detail-header h3 { font-size: 0.95rem; }
        .detail-body { padding: 16px; }
        .list-item { padding: 12px 16px; border-bottom: 1px solid var(--border); display: flex; justify-content: space-between; align-items: center; }
        .list-item:last-child { border-bottom: none; }
        .list-item:hover { background: var(--bg-tertiary); }
        .list-item-content h4 { font-weight: 500; margin-bottom: 2px; font-size: 0.9rem; }
        .list-item-content p { font-size: 0.75rem; color: var(--text-secondary); }
        .todo-item { display: flex; gap: 10px; padding: 10px; border-radius: 6px; margin-bottom: 6px; background: var(--bg-tertiary); }
        .todo-checkbox { width: 16px; height: 16px; border-radius: 4px; border: 2px solid var(--border); flex-shrink: 0; margin-top: 2px; }
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
        <nav class="sidebar" id="sidebar"></nav>
        <main class="main">
            <div class="main-header" id="mainHeader"></div>
            <div class="main-content" id="mainContent"></div>
        </main>
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
const data = %%DATA_PLACEHOLDER%%;

let currentView = 'dashboard';
let currentProject = null;
let currentSession = null;

const fmt = {
    num: n => n >= 1e6 ? (n/1e6).toFixed(1)+'M' : n >= 1e3 ? (n/1e3).toFixed(1)+'K' : n.toString(),
    bytes: b => b >= 1048576 ? (b/1048576).toFixed(1)+' MB' : b >= 1024 ? (b/1024).toFixed(1)+' KB' : b+' B',
    duration: ms => Math.floor(ms/3600000)+'h '+Math.floor((ms%3600000)/60000)+'m',
    date: ts => ts ? new Date(ts).toLocaleString() : '',
    shortDate: ts => ts ? new Date(ts).toLocaleDateString() : '',
    path: p => p.replace(/-/g, '/').replace(/^\\//, ''),
    escape: t => { const d = document.createElement('div'); d.textContent = t; return d.innerHTML; }
};

function buildSidebar() {
    document.getElementById('sidebar').innerHTML = `
        <div class="logo"><h1>Claude Explorer</h1><span>~/.claude Deep Dive</span></div>
        <div class="nav-section">
            <div class="nav-section-title">Overview</div>
            <div class="nav-item ${currentView==='dashboard'?'active':''}" onclick="navigate('dashboard')">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/></svg>
                Dashboard
            </div>
        </div>
        <div class="nav-section">
            <div class="nav-section-title">Sessions</div>
            <div class="nav-item ${currentView==='history'?'active':''}" onclick="navigate('history')">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
                History <span class="count">${data.history?.length||0}</span>
            </div>
            <div class="nav-item ${currentView==='projects'?'active':''}" onclick="navigate('projects')">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 19a2 2 0 01-2 2H4a2 2 0 01-2-2V5a2 2 0 012-2h5l2 3h9a2 2 0 012 2z"/></svg>
                Projects <span class="count">${data.projects?.length||0}</span>
            </div>
        </div>
        <div class="nav-section">
            <div class="nav-section-title">Content</div>
            <div class="nav-item ${currentView==='plans'?'active':''}" onclick="navigate('plans')">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
                Plans <span class="count">${data.plans?.length||0}</span>
            </div>
            <div class="nav-item ${currentView==='todos'?'active':''}" onclick="navigate('todos')">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11"/></svg>
                Todos <span class="count">${data.todos?.length||0}</span>
            </div>
            <div class="nav-item ${currentView==='skills'?'active':''}" onclick="navigate('skills')">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>
                Skills <span class="count">${data.skills?.length||0}</span>
            </div>
        </div>
        <div class="nav-section">
            <div class="nav-section-title">Config</div>
            <div class="nav-item ${currentView==='settings'?'active':''}" onclick="navigate('settings')">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83 0 2 2 0 010-2.83l.06-.06a1.65 1.65 0 00.33-1.82 1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 010-2.83 2 2 0 012.83 0l.06.06a1.65 1.65 0 001.82.33H9a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 0 2 2 0 010 2.83l-.06.06a1.65 1.65 0 00-.33 1.82V9c.26.604.852.997 1.51 1H21a2 2 0 010 4h-.09a1.65 1.65 0 00-1.51 1z"/></svg>
                Settings
            </div>
            <div class="nav-item ${currentView==='plugins'?'active':''}" onclick="navigate('plugins')">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"/></svg>
                Plugins
            </div>
        </div>
    `;
}

function navigate(view, proj, sess) {
    currentView = view;
    currentProject = proj || null;
    currentSession = sess || null;
    buildSidebar();
    render();
}

function render() {
    const header = document.getElementById('mainHeader');
    const content = document.getElementById('mainContent');
    switch(currentView) {
        case 'dashboard': renderDashboard(header, content); break;
        case 'history': renderHistory(header, content); break;
        case 'projects': renderProjects(header, content); break;
        case 'project': renderProject(header, content); break;
        case 'session': renderSession(header, content); break;
        case 'plans': renderPlans(header, content); break;
        case 'todos': renderTodos(header, content); break;
        case 'skills': renderSkills(header, content); break;
        case 'settings': renderSettings(header, content); break;
        case 'plugins': renderPlugins(header, content); break;
    }
}

function renderDashboard(header, content) {
    const s = data.stats || {}, u = Object.values(s.modelUsage || {})[0] || {};
    header.innerHTML = '<h2>Dashboard</h2><p>Claude Code usage overview</p>';
    content.innerHTML = `
        <div class="stats-grid">
            <div class="stat-card"><div class="label">Sessions</div><div class="value">${s.totalSessions||0}</div><div class="subtitle">Since ${s.firstSessionDate?fmt.shortDate(s.firstSessionDate):'N/A'}</div></div>
            <div class="stat-card"><div class="label">Messages</div><div class="value">${fmt.num(s.totalMessages||0)}</div></div>
            <div class="stat-card"><div class="label">Longest</div><div class="value">${s.longestSession?fmt.duration(s.longestSession.duration):'N/A'}</div><div class="subtitle">${s.longestSession?.messageCount||0} msgs</div></div>
            <div class="stat-card"><div class="label">Projects</div><div class="value">${data.projects?.length||0}</div></div>
        </div>
        <div class="chart-container"><h3>Activity</h3><div class="chart-wrapper"><canvas id="activityChart"></canvas></div></div>
        <div class="two-col">
            <div class="chart-container"><h3>By Hour</h3><div class="hour-chart" id="hourChart"></div></div>
            <div class="chart-container"><h3>Tokens</h3>
                <div class="token-stat input"><div class="label">Input</div><div class="value">${fmt.num(u.inputTokens||0)}</div></div>
                <div class="token-stat output"><div class="label">Output</div><div class="value">${fmt.num(u.outputTokens||0)}</div></div>
                <div class="token-stat cache"><div class="label">Cache</div><div class="value">${fmt.num(u.cacheReadInputTokens||0)}</div></div>
            </div>
        </div>
    `;
    initCharts();
}

function renderHistory(header, content) {
    const h = data.history || [];
    const projs = [...new Set(h.map(x=>x.project?.split('/').pop()).filter(Boolean))];
    header.innerHTML = `<h2>History</h2><p>${h.length} entries</p>`;
    content.innerHTML = `
        <div class="search-box"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg><input type="text" placeholder="Search..." oninput="filterRows('.history-row', this.value)"></div>
        <div class="filters"><button class="filter-btn active" onclick="filterByAttr('.history-row','data-project','all',this)">All</button>${projs.map(p=>`<button class="filter-btn" onclick="filterByAttr('.history-row','data-project','${p}',this)">${p}</button>`).join('')}</div>
        <div class="table-container"><div class="table-scroll"><table><thead><tr><th>Message</th><th>Project</th><th>Time</th></tr></thead>
        <tbody>${h.slice(0,300).map((x,i)=>`<tr class="history-row" data-project="${x.project?.split('/').pop()||''}" style="cursor:pointer" onclick="showHistoryDetail(${i})"><td>${fmt.escape((x.display||'').substring(0,100))}${(x.display||'').length>100?'...':''}</td><td><span class="badge badge-accent">${x.project?.split('/').pop()||''}</span></td><td style="white-space:nowrap;color:var(--text-secondary)">${x.timestamp?fmt.date(x.timestamp):''}</td></tr>`).join('')}</tbody></table></div></div>
    `;
}

function renderProjects(header, content) {
    header.innerHTML = `<h2>Projects</h2><p>${data.projects?.length||0} projects with session data</p>`;
    content.innerHTML = `<div class="card-grid">${(data.projects||[]).map(p=>`
        <div class="card" onclick="navigate('project','${p.path}')">
            <div class="card-title">${fmt.path(p.path).split('/').pop()}</div>
            <div class="card-meta">${fmt.path(p.path)}</div>
            <div class="card-content"><span class="badge badge-info">${p.sessionCount} sessions</span> <span class="badge badge-accent">${p.sessions.reduce((a,s)=>a+s.messageCount,0)} messages</span></div>
        </div>
    `).join('')}</div>`;
}

function renderProject(header, content) {
    const p = data.projects?.find(x=>x.path===currentProject);
    if (!p) return navigate('projects');
    const name = fmt.path(p.path).split('/').pop();
    header.innerHTML = `<div class="breadcrumb"><a onclick="navigate('projects')">Projects</a><span>/</span><span>${name}</span></div><h2>${name}</h2><p>${p.sessionCount} sessions</p>`;
    content.innerHTML = `<div class="session-list">${p.sessions.map(s=>`
        <div class="session-item" onclick="navigate('session','${p.path}','${s.id}')">
            <div class="session-item-header">
                <div class="session-item-title">Session ${s.id.substring(0,8)}...</div>
                <div class="session-item-meta">${s.messageCount} messages - ${fmt.bytes(s.size)}</div>
            </div>
            <div class="session-item-preview">${fmt.escape(s.preview||'')}</div>
            <div class="session-item-meta" style="margin-top:6px">${s.firstTimestamp?fmt.date(s.firstTimestamp):''}</div>
        </div>
    `).join('')}</div>`;
}

function renderSession(header, content) {
    const p = data.projects?.find(x=>x.path===currentProject);
    const s = p?.sessions?.find(x=>x.id===currentSession);
    if (!p || !s) return navigate('projects');
    const name = fmt.path(p.path).split('/').pop();
    header.innerHTML = `<div class="breadcrumb"><a onclick="navigate('projects')">Projects</a><span>/</span><a onclick="navigate('project','${p.path}')">${name}</a><span>/</span><span>Session</span></div><h2>Session ${s.id.substring(0,8)}...</h2><p>${s.messageCount} messages - ${s.firstTimestamp?fmt.date(s.firstTimestamp):''}</p>`;
    content.innerHTML = `<div class="conversation">${s.messages.map(m=>`
        <div class="message ${m.role}">
            <div class="message-header">
                <div class="message-role">${m.role}</div>
                <div class="message-time">${m.timestamp?fmt.date(m.timestamp):''}</div>
            </div>
            <div class="message-content">${formatMessageContent(m.content)}</div>
        </div>
    `).join('')}</div>`;
}

function formatMessageContent(content) {
    if (!content) return '';
    let html = fmt.escape(content);
    html = html.replace(/\\[Tool: ([^\\]]+)\\]/g, '<div class="tool-call">Tool: $1</div>');
    html = html.replace(/\\[Tool Result: ([^\\]]+)\\]/g, '<div class="tool-call">Result: $1</div>');
    html = html.replace(/```(\\w*)\\n([\\s\\S]*?)```/g, '<pre><code>$2</code></pre>');
    html = html.replace(/`([^`]+)`/g, '<code>$1</code>');
    return html;
}

function renderPlans(header, content) {
    header.innerHTML = `<h2>Plans</h2><p>${data.plans?.length||0} implementation plans</p>`;
    content.innerHTML = `<div class="card-grid">${(data.plans||[]).map((p,i)=>`
        <div class="card" onclick="showPlanDetail(${i})">
            <div class="card-title">${p.name}</div>
            <div class="card-meta">${fmt.bytes(p.size)} - ${p.modified}</div>
            <div class="card-content">${(p.content||'').substring(0,150)}...</div>
        </div>
    `).join('')}</div>`;
}

function renderTodos(header, content) {
    const t = data.todos || [];
    header.innerHTML = `<h2>Todos</h2><p>${t.length} task lists</p>`;
    if (!t.length) { content.innerHTML = '<div class="empty-state">No todos</div>'; return; }
    content.innerHTML = t.map(todo=>`
        <div class="detail-panel">
            <div class="detail-header"><h3>Session ${todo.id.substring(0,8)}...</h3><span class="badge badge-info">${Array.isArray(todo.tasks)?todo.tasks.length:0} tasks</span></div>
            <div class="detail-body">${Array.isArray(todo.tasks)?todo.tasks.map(task=>`
                <div class="todo-item ${task.status==='completed'?'completed':''}">
                    <div class="todo-checkbox"></div>
                    <div class="todo-content"><div>${fmt.escape(task.content||'')}</div><span class="badge ${task.status==='completed'?'badge-success':'badge-warning'}">${task.status||'pending'}</span></div>
                </div>
            `).join(''):'<div class="empty-state">No tasks</div>'}</div>
        </div>
    `).join('');
}

function renderSkills(header, content) {
    header.innerHTML = `<h2>Skills</h2><p>${data.skills?.length||0} custom skills</p>`;
    content.innerHTML = `<div class="card-grid">${(data.skills||[]).map((s,i)=>`
        <div class="card" onclick="showSkillDetail(${i})">
            <div class="card-title">${s.name}</div>
            <div class="card-meta">Files: ${s.files?.join(', ')||'N/A'}</div>
            <div class="card-content">${s.content?s.content.substring(0,150)+'...':'No SKILL.md'}</div>
        </div>
    `).join('')||'<div class="empty-state">No skills</div>'}</div>`;
}

function renderSettings(header, content) {
    header.innerHTML = '<h2>Settings</h2><p>Configuration files</p>';
    content.innerHTML = `
        <div class="detail-panel"><div class="detail-header"><h3>settings.json</h3></div><div class="detail-body"><div class="code-block">${JSON.stringify(data.settings||{},null,2)}</div></div></div>
        <div class="detail-panel"><div class="detail-header"><h3>settings.local.json</h3></div><div class="detail-body"><div class="code-block">${JSON.stringify(data.settingsLocal||{},null,2)}</div></div></div>
    `;
}

function renderPlugins(header, content) {
    const p = data.installedPlugins?.plugins || {}, m = data.marketplaces || {};
    header.innerHTML = '<h2>Plugins</h2><p>Installed plugins and marketplaces</p>';
    content.innerHTML = `
        <div class="detail-panel"><div class="detail-header"><h3>Installed</h3></div>${Object.entries(p).map(([n,v])=>`<div class="list-item"><div class="list-item-content"><h4>${n}</h4><p>v${v[0]?.version||'?'}</p></div><span class="badge badge-success">Installed</span></div>`).join('')||'<div class="empty-state">None</div>'}</div>
        <div class="detail-panel"><div class="detail-header"><h3>Marketplaces</h3></div>${Object.entries(m).map(([n,i])=>`<div class="list-item"><div class="list-item-content"><h4>${n}</h4><p>${i.source?.repo||''}</p></div><span class="badge badge-accent">Active</span></div>`).join('')||'<div class="empty-state">None</div>'}</div>
    `;
}

function initCharts() {
    const s = data.stats || {};
    const ctx = document.getElementById('activityChart')?.getContext('2d');
    if (ctx && s.dailyActivity) {
        new Chart(ctx, {
            type: 'line',
            data: {
                labels: s.dailyActivity.map(d => new Date(d.date).toLocaleDateString('en-US', {month:'short',day:'numeric'})),
                datasets: [{label:'Messages',data:s.dailyActivity.map(d=>d.messageCount),borderColor:'#c9885a',backgroundColor:'rgba(201,136,90,0.1)',fill:true,tension:0.4},{label:'Tools',data:s.dailyActivity.map(d=>d.toolCallCount),borderColor:'#3fb950',backgroundColor:'rgba(63,185,80,0.1)',fill:true,tension:0.4}]
            },
            options: {responsive:true,maintainAspectRatio:false,plugins:{legend:{labels:{color:'#8b949e'}}},scales:{x:{grid:{color:'#30363d'},ticks:{color:'#8b949e'}},y:{grid:{color:'#30363d'},ticks:{color:'#8b949e'}}}}
        });
    }
    const hc = document.getElementById('hourChart');
    if (hc && s.hourCounts) {
        const max = Math.max(...Object.values(s.hourCounts), 1);
        for (let h=0;h<24;h++) { const bar=document.createElement('div'); bar.className='hour-bar'; bar.style.height=((s.hourCounts[h]||0)/max*100||3)+'%'; bar.title=h+':00'; hc.appendChild(bar); }
    }
}

function filterRows(selector, query) {
    const q = query.toLowerCase();
    document.querySelectorAll(selector).forEach(r => { r.style.display = r.textContent.toLowerCase().includes(q) ? '' : 'none'; });
}
function filterByAttr(selector, attr, val, btn) {
    document.querySelectorAll('.filter-btn').forEach(b=>b.classList.remove('active'));
    btn.classList.add('active');
    document.querySelectorAll(selector).forEach(r => { r.style.display = val==='all'||r.getAttribute(attr)===val ? '' : 'none'; });
}

function showModal(title, body) {
    document.getElementById('modalTitle').textContent = title;
    document.getElementById('modalBody').innerHTML = body;
    document.getElementById('modal').classList.add('active');
}
function closeModal() { document.getElementById('modal').classList.remove('active'); }
document.getElementById('modal').addEventListener('click', e => { if(e.target.id==='modal') closeModal(); });
document.addEventListener('keydown', e => { if(e.key==='Escape') closeModal(); });

function showHistoryDetail(i) {
    const h = data.history[i];
    showModal('Message', `<div class="detail-body"><div class="code-block">${fmt.escape(h.display||'')}</div><div style="margin-top:12px;font-size:0.85rem;color:var(--text-secondary)"><div>Project: ${h.project||'N/A'}</div><div>Session: ${h.sessionId||'N/A'}</div><div>Time: ${h.timestamp?fmt.date(h.timestamp):'N/A'}</div></div></div>`);
}
function showPlanDetail(i) {
    const p = data.plans[i];
    showModal(p.name, `<div class="markdown-content">${typeof marked!=='undefined'?marked.parse(p.content||''):`<pre>${fmt.escape(p.content||'')}</pre>`}</div>`);
}
function showSkillDetail(i) {
    const s = data.skills[i];
    showModal(s.name, `<div class="detail-body"><div class="code-block">${s.files?.join('\\n')||'No files'}</div></div><div class="markdown-content">${s.content?(typeof marked!=='undefined'?marked.parse(s.content):`<pre>${fmt.escape(s.content)}</pre>`):'<p style="color:var(--text-secondary)">No SKILL.md</p>'}</div>`);
}

buildSidebar();
render();
    </script>
</body>
</html>'''

def build_html(data, output_path, verbose=False):
    """Build the HTML file with embedded data."""
    template = get_html_template()
    data_json = json.dumps(data)
    # Escape </script> to prevent breaking HTML parsing
    data_json = data_json.replace('</script>', '<\\/script>')
    html = template.replace('%%DATA_PLACEHOLDER%%', data_json)

    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(html)

    if verbose:
        size = output_path.stat().st_size
        size_str = f"{size/1024/1024:.1f} MB" if size > 1024*1024 else f"{size/1024:.1f} KB"
        print(f"Generated: {output_path} ({size_str})")

    return output_path

def open_in_browser(path):
    """Open the HTML file in the default browser."""
    path = Path(path).resolve()
    if sys.platform == 'darwin':
        subprocess.run(['open', str(path)])
    elif sys.platform == 'win32':
        os.startfile(str(path))
    else:
        subprocess.run(['xdg-open', str(path)])

def main():
    parser = argparse.ArgumentParser(
        prog='claude-explorer',
        description='Interactive viewer for Claude Code session data (~/.claude)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  claude-explorer                    # Generate and open explorer
  claude-explorer --no-open          # Generate without opening browser
  claude-explorer -o ~/Desktop/claude.html  # Custom output location
  claude-explorer --max-sessions 50  # Include more sessions per project
        '''
    )

    parser.add_argument('-V', '--version', action='version', version=f'%(prog)s {VERSION}')

    parser.add_argument(
        '-d', '--claude-dir',
        type=Path,
        default=get_default_claude_dir(),
        help=f'Path to Claude directory (default: ~/.claude)'
    )

    parser.add_argument(
        '-o', '--output',
        type=Path,
        default=get_default_output(),
        help=f'Output HTML file path (default: ~/claude-explorer.html)'
    )

    parser.add_argument(
        '--no-open',
        action='store_true',
        help='Do not open the browser after generating'
    )

    parser.add_argument(
        '--max-sessions',
        type=int,
        default=20,
        help='Maximum sessions per project (default: 20)'
    )

    parser.add_argument(
        '--max-messages',
        type=int,
        default=500,
        help='Maximum messages per session (default: 500)'
    )

    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Show detailed progress'
    )

    parser.add_argument(
        '--json',
        action='store_true',
        help='Output raw JSON data instead of HTML'
    )

    args = parser.parse_args()

    # Extract data
    if args.verbose:
        print("Claude Explorer v" + VERSION)
        print("-" * 40)

    data = extract_data(
        args.claude_dir,
        max_sessions=args.max_sessions,
        max_messages=args.max_messages,
        verbose=args.verbose
    )

    # Output JSON if requested
    if args.json:
        print(json.dumps(data, indent=2))
        return

    # Build HTML
    output_path = build_html(data, args.output, verbose=args.verbose)

    # Open in browser
    if not args.no_open:
        if args.verbose:
            print(f"Opening in browser...")
        open_in_browser(output_path)
    else:
        print(f"Generated: {output_path}")

if __name__ == '__main__':
    main()
