# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Explorer is a Python CLI tool that generates an interactive HTML dashboard for exploring Claude Code session history stored in `~/.claude`. It reads session data, settings, plans, skills, and usage statistics, then outputs a self-contained HTML file with embedded JavaScript.

## Build & Run Commands

```bash
# Run directly (no installation needed)
./claude-explorer

# Run with Python
python claude_explorer.py

# Run with verbose output
./claude-explorer -v

# Generate without opening browser
./claude-explorer --no-open

# Output raw JSON instead of HTML
./claude-explorer --json > claude-data.json

# Run tests
python -m pytest tests/
```

## Architecture

The codebase is a single-file Python script (`claude_explorer.py`) with these main components:

1. **Data Extraction** (`extract_data`): Reads from `~/.claude` directory including:
   - `settings.json`, `settings.local.json` - configuration
   - `stats-cache.json` - usage statistics
   - `history.jsonl` - command history
   - `projects/` - session transcripts (JSONL files)
   - `plans/` - implementation plans (Markdown)
   - `skills/` - custom skills with SKILL.md files
   - `todos/` - task lists (JSON)
   - `plugins/` - installed plugins

2. **HTML Generation** (`get_html_template`, `build_html`): Embeds extracted data as JSON into a self-contained HTML template with:
   - CSS styling (dark theme, KAYMO brand colors)
   - JavaScript SPA for navigation between views
   - Chart.js for activity visualization
   - Marked.js for Markdown rendering

3. **Session Parsing** (`parse_session`): Reads JSONL session files and extracts user/assistant messages with timestamps and tool calls.

The `claude-explorer` executable is a symlink to `claude_explorer.py`.

## Key Functions

- `safe_read_json/safe_read_jsonl`: Error-tolerant file readers
- `extract_message_content`: Handles various message content formats (string, list of text/tool_use)
- `parse_session`: Converts JSONL session files to message objects
- `extract_data`: Main data collection from ~/.claude
- `build_html`: Template substitution with JSON data embedding
