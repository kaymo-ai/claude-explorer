#!/bin/bash
# Extract all ~/.claude data into a JSON file for the explorer

CLAUDE_DIR="$HOME/.claude"
OUTPUT_FILE="$(dirname "$0")/claude-data.json"

echo "Extracting Claude data from $CLAUDE_DIR..."

# Start JSON
echo '{' > "$OUTPUT_FILE"

# Settings
echo '  "settings": ' >> "$OUTPUT_FILE"
cat "$CLAUDE_DIR/settings.json" >> "$OUTPUT_FILE"
echo ',' >> "$OUTPUT_FILE"

echo '  "settingsLocal": ' >> "$OUTPUT_FILE"
cat "$CLAUDE_DIR/settings.local.json" >> "$OUTPUT_FILE"
echo ',' >> "$OUTPUT_FILE"

# Stats
echo '  "stats": ' >> "$OUTPUT_FILE"
cat "$CLAUDE_DIR/stats-cache.json" >> "$OUTPUT_FILE"
echo ',' >> "$OUTPUT_FILE"

# Plugins
echo '  "installedPlugins": ' >> "$OUTPUT_FILE"
cat "$CLAUDE_DIR/plugins/installed_plugins.json" >> "$OUTPUT_FILE"
echo ',' >> "$OUTPUT_FILE"

echo '  "marketplaces": ' >> "$OUTPUT_FILE"
cat "$CLAUDE_DIR/plugins/known_marketplaces.json" >> "$OUTPUT_FILE"
echo ',' >> "$OUTPUT_FILE"

# History (full)
echo '  "history": [' >> "$OUTPUT_FILE"
first=true
while IFS= read -r line; do
    if [ "$first" = true ]; then
        first=false
    else
        echo ',' >> "$OUTPUT_FILE"
    fi
    echo "    $line" >> "$OUTPUT_FILE"
done < "$CLAUDE_DIR/history.jsonl"
echo '  ],' >> "$OUTPUT_FILE"

# Plans (with full content)
echo '  "plans": [' >> "$OUTPUT_FILE"
first=true
for plan in "$CLAUDE_DIR/plans/"*.md; do
    if [ -f "$plan" ]; then
        if [ "$first" = true ]; then
            first=false
        else
            echo ',' >> "$OUTPUT_FILE"
        fi
        filename=$(basename "$plan")
        name="${filename%.md}"
        size=$(wc -c < "$plan" | tr -d ' ')
        modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$plan" 2>/dev/null || stat -c "%y" "$plan" 2>/dev/null | cut -d' ' -f1,2)
        # Escape content for JSON
        content=$(cat "$plan" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
        echo "    {\"name\": \"$name\", \"file\": \"$filename\", \"size\": $size, \"modified\": \"$modified\", \"content\": $content}" >> "$OUTPUT_FILE"
    fi
done
echo '  ],' >> "$OUTPUT_FILE"

# Projects
echo '  "projects": [' >> "$OUTPUT_FILE"
first=true
for proj in "$CLAUDE_DIR/projects/"*/; do
    if [ -d "$proj" ]; then
        if [ "$first" = true ]; then
            first=false
        else
            echo ',' >> "$OUTPUT_FILE"
        fi
        dirname=$(basename "$proj")
        # Count sessions
        session_count=$(ls "$proj"*.jsonl 2>/dev/null | wc -l | tr -d ' ')
        # Get session files
        sessions="["
        sfirst=true
        for session in "$proj"*.jsonl; do
            if [ -f "$session" ]; then
                if [ "$sfirst" = true ]; then
                    sfirst=false
                else
                    sessions="$sessions,"
                fi
                sname=$(basename "$session" .jsonl)
                ssize=$(wc -c < "$session" | tr -d ' ')
                slines=$(wc -l < "$session" | tr -d ' ')
                sessions="$sessions{\"id\": \"$sname\", \"size\": $ssize, \"lines\": $slines}"
            fi
        done
        sessions="$sessions]"
        echo "    {\"path\": \"$dirname\", \"sessionCount\": $session_count, \"sessions\": $sessions}" >> "$OUTPUT_FILE"
    fi
done
echo '  ],' >> "$OUTPUT_FILE"

# Skills
echo '  "skills": [' >> "$OUTPUT_FILE"
first=true
for skill in "$CLAUDE_DIR/skills/"*/; do
    if [ -d "$skill" ]; then
        if [ "$first" = true ]; then
            first=false
        else
            echo ',' >> "$OUTPUT_FILE"
        fi
        skillname=$(basename "$skill")
        # Read SKILL.md if exists
        skillcontent=""
        if [ -f "$skill/SKILL.md" ]; then
            skillcontent=$(cat "$skill/SKILL.md" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
        else
            skillcontent='""'
        fi
        # List files
        files=$(ls "$skill" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip().split("\n")))')
        echo "    {\"name\": \"$skillname\", \"content\": $skillcontent, \"files\": $files}" >> "$OUTPUT_FILE"
    fi
done
echo '  ],' >> "$OUTPUT_FILE"

# Todos
echo '  "todos": [' >> "$OUTPUT_FILE"
first=true
for todo in "$CLAUDE_DIR/todos/"*.json; do
    if [ -f "$todo" ]; then
        content=$(cat "$todo" 2>/dev/null)
        # Skip if empty or just "[]"
        if [ -n "$content" ] && [ "$content" != "[]" ]; then
            if [ "$first" = true ]; then
                first=false
            else
                echo ',' >> "$OUTPUT_FILE"
            fi
            todoname=$(basename "$todo" .json)
            echo "    {\"id\": \"$todoname\", \"tasks\": $content}" >> "$OUTPUT_FILE"
        fi
    fi
done
echo '  ],' >> "$OUTPUT_FILE"

# File history sessions
echo '  "fileHistory": [' >> "$OUTPUT_FILE"
first=true
for fh in "$CLAUDE_DIR/file-history/"*/; do
    if [ -d "$fh" ]; then
        if [ "$first" = true ]; then
            first=false
        else
            echo ',' >> "$OUTPUT_FILE"
        fi
        fhname=$(basename "$fh")
        filecount=$(ls "$fh" 2>/dev/null | wc -l | tr -d ' ')
        # List versioned files
        files="["
        ffirst=true
        for f in "$fh"*; do
            if [ -f "$f" ]; then
                if [ "$ffirst" = true ]; then
                    ffirst=false
                else
                    files="$files,"
                fi
                fname=$(basename "$f")
                fsize=$(wc -c < "$f" | tr -d ' ')
                files="$files{\"name\": \"$fname\", \"size\": $fsize}"
            fi
        done
        files="$files]"
        echo "    {\"sessionId\": \"$fhname\", \"fileCount\": $filecount, \"files\": $files}" >> "$OUTPUT_FILE"
    fi
done
echo '  ]' >> "$OUTPUT_FILE"

# Close JSON
echo '}' >> "$OUTPUT_FILE"

echo "Done! Data extracted to $OUTPUT_FILE"
echo "File size: $(wc -c < "$OUTPUT_FILE" | tr -d ' ') bytes"
