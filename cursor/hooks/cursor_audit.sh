#!/bin/zsh
# Cursor Hooks Audit Script (Shell - macOS)
# No external dependencies - uses only built-in shell commands.

MCP_GATEWAY_DIR="$HOME/.mcp-gateway"
LOG_DIR="$MCP_GATEWAY_DIR/logs"
LOGGING_CONFIG_FILE="$MCP_GATEWAY_DIR/logging_config.json"
mkdir -p "$LOG_DIR"

input_json=$(cat)
[[ -z "$input_json" ]] && exit 0

# Function to extract a string value from JSON using regex
# Usage: extract_json_string "key" "$json"
extract_json_string() {
    local key="$1"
    local json="$2"
    local value=""
    # Match "key": "value" or "key":"value", handling escaped quotes in value
    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*\"([^\"\\]*(\\.[^\"\\]*)*)\" ]]; then
        value="${match[1]}"
        # Unescape common JSON escapes for storage (leave as-is for re-embedding in JSON)
        value="${value//\\\"/\"}"
        value="${value//\\\\/\\}"
    fi
    echo "$value"
}

# Function to extract a number or null value from JSON
extract_json_number() {
    local key="$1"
    local json="$2"
    local value=""
    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*([0-9]+|null) ]]; then
        value="${match[1]}"
    fi
    echo "$value"
}

# Function to extract an array from JSON (returns raw JSON array)
extract_json_array() {
    local key="$1"
    local json="$2"
    local value="[]"
    # Simple extraction - finds array start and counts brackets
    if [[ "$json" =~ \"$key\"[[:space:]]*:[[:space:]]*[[] ]]; then
        # Find the position of "key" in the string, then scan forward for '['
        local search_str="\"$key\""
        local prefix="${json%%$search_str*}"
        local start_pos=${#prefix}
        local bracket_count=0
        local in_string=false
        local escaped=false
        local arr_start=0
        local i=$start_pos

        # Find the opening bracket position
        while [[ $i -le ${#json} ]]; do
            local char="${json:$i:1}"
            if [[ "$char" == "[" ]] && [[ $arr_start -eq 0 ]]; then
                arr_start=$i
                break
            fi
            ((i++))
        done

        # Now find the matching closing bracket
        i=$arr_start
        while [[ $i -le ${#json} ]]; do
            local char="${json:$i:1}"
            if $escaped; then
                escaped=false
            elif [[ "$char" == "\\" ]]; then
                escaped=true
            elif [[ "$char" == '"' ]]; then
                if $in_string; then in_string=false; else in_string=true; fi
            elif ! $in_string; then
                if [[ "$char" == "[" ]]; then
                    ((bracket_count++))
                elif [[ "$char" == "]" ]]; then
                    ((bracket_count--))
                    if [[ $bracket_count -eq 0 ]]; then
                        value="${json:$arr_start:$((i - arr_start + 1))}"
                        break
                    fi
                fi
            fi
            ((i++))
        done
    fi
    echo "$value"
}

# Function to escape a string for JSON embedding
escape_for_json() {
    local str="$1"
    # Escape backslashes first, then quotes, then control characters
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    # Remove null bytes and other control characters (0x00-0x1F except \n \r \t)
    str="${str//$'\x00'/}"
    str="${str//$'\x01'/}"
    str="${str//$'\x02'/}"
    str="${str//$'\x03'/}"
    str="${str//$'\x04'/}"
    str="${str//$'\x05'/}"
    str="${str//$'\x06'/}"
    str="${str//$'\x07'/}"
    str="${str//$'\x08'/}"
    str="${str//$'\x0b'/}"
    str="${str//$'\x0c'/}"
    str="${str//$'\x0e'/}"
    str="${str//$'\x0f'/}"
    str="${str//$'\x10'/}"
    str="${str//$'\x11'/}"
    str="${str//$'\x12'/}"
    str="${str//$'\x13'/}"
    str="${str//$'\x14'/}"
    str="${str//$'\x15'/}"
    str="${str//$'\x16'/}"
    str="${str//$'\x17'/}"
    str="${str//$'\x18'/}"
    str="${str//$'\x19'/}"
    str="${str//$'\x1a'/}"
    str="${str//$'\x1b'/}"
    str="${str//$'\x1c'/}"
    str="${str//$'\x1d'/}"
    str="${str//$'\x1e'/}"
    str="${str//$'\x1f'/}"
    echo "$str"
}

# Truncate string to max characters to prevent oversized log entries
MAX_FIELD_CHARS=10240  # ~10KB default
truncate_field() {
    local str="$1"
    local max="${2:-$MAX_FIELD_CHARS}"
    if [[ ${#str} -gt $max ]]; then
        echo "${str:0:$max}...(truncated)"
    else
        echo "$str"
    fi
}

# Extract hook event name first (needed to determine which fields to parse)
hook_event=$(extract_json_string "hook_event_name" "$input_json")

# Early exit if hook event is empty/unknown
if [[ -z "$hook_event" ]]; then
    exit 0
fi

# Extract common metadata fields (lightweight string extractions)
user_email=$(extract_json_string "user_email" "$input_json")
conversation_id=$(extract_json_string "conversation_id" "$input_json")
generation_id=$(extract_json_string "generation_id" "$input_json")
model=$(extract_json_string "model" "$input_json")
cursor_version=$(extract_json_string "cursor_version" "$input_json")

# Check if Cursor logging is enabled
cursor_logging_enabled=true
if [[ -f "$LOGGING_CONFIG_FILE" ]]; then
    if [[ "$(extract_json_string "cursor_logging_enabled" "$(<"$LOGGING_CONFIG_FILE")")" == "false" ]]; then
        cursor_logging_enabled=false
    fi
fi

# Get log file from environment or find the gateway for THIS Cursor session
if [[ -n "$MCP_GATEWAY_LOG_FILE" ]] && [[ -f "$MCP_GATEWAY_LOG_FILE" ]]; then
    log_file="$MCP_GATEWAY_LOG_FILE"
else
    # Fallback: Find the gateway process that belongs to our parent Cursor session
    parent_pid=$(ps -o ppid= -p $$ | tr -d ' ')
    gateway_pid=$(ps -ef | awk -v ppid="$parent_pid" '$3 == ppid && $8 ~ /mcp-gateway/ {print $2; exit}')

    if [[ -n "$gateway_pid" ]]; then
        log_file=$(ls -1 "$LOG_DIR"/gateway_${gateway_pid}_*.log 2>/dev/null | head -1)
    fi

    if [[ -z "$log_file" ]]; then
        if [[ -n "$gateway_pid" ]]; then
            timestamp=$(date +%Y-%m-%d_%H-%M-%S)
            log_file="$LOG_DIR/gateway_${gateway_pid}_${timestamp}.log"
            touch "$log_file"
        else
            log_file=$(ls -t "$LOG_DIR"/gateway_*_*.log 2>/dev/null | head -1)
            if [[ -z "$log_file" ]]; then
                timestamp=$(date +%Y-%m-%d_%H-%M-%S)
                log_file="$LOG_DIR/gateway_$$_${timestamp}.log"
                touch "$log_file"
            fi
        fi
    fi
fi

# Check if log rotation needed (50MB or 4 hours old)
# Gateway rotates every 10 min, so hooks use longer interval to avoid race conditions
MAX_LOG_SIZE_MB=50
MAX_LOG_AGE_SEC=14400

if [[ -f "$log_file" ]]; then
    file_size_mb=$(du -m "$log_file" | cut -f1)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        file_mtime=$(stat -f %m "$log_file" 2>/dev/null || echo 0)
    else
        file_mtime=$(stat -c %Y "$log_file" 2>/dev/null || echo 0)
    fi
    current_time=$(date +%s)
    file_age=$((current_time - file_mtime))

    if [[ $file_size_mb -ge $MAX_LOG_SIZE_MB ]] || [[ $file_age -ge $MAX_LOG_AGE_SEC ]]; then
        mv "$log_file" "${log_file}.complete" 2>/dev/null
        pid=${MCP_GATEWAY_PID:-$$}
        timestamp=$(date +%Y-%m-%d_%H-%M-%S)
        log_file="$LOG_DIR/gateway_${pid}_${timestamp}.log"
        touch "$log_file"
    fi
fi

# Build log entry
escaped_user_id=$(escape_for_json "${user_email:-$USER}")
ts=$(date +"%Y-%m-%d %H:%M:%S,000")
unix_ts=$(date +%s)

# Extract fields and build event_data lazily based on hook type
# Only parse expensive fields (arrays, large strings) when needed
event_data=""
case "$hook_event" in
    "beforeSubmitPrompt")
        escaped_prompt=$(escape_for_json "$(truncate_field "$(extract_json_string "prompt" "$input_json")")")
        attachments=$(extract_json_array "attachments" "$input_json")
        event_data="\"event_data\":{\"prompt\":\"$escaped_prompt\",\"attachments\":$attachments}"
        ;;
    "afterAgentResponse")
        escaped_text=$(escape_for_json "$(truncate_field "$(extract_json_string "text" "$input_json")")")
        event_data="\"event_data\":{\"response_text\":\"$escaped_text\"}"
        ;;
    "afterAgentThought")
        escaped_text=$(escape_for_json "$(truncate_field "$(extract_json_string "text" "$input_json")")")
        duration_ms=$(extract_json_number "duration_ms" "$input_json")
        event_data="\"event_data\":{\"thought_text\":\"$escaped_text\",\"duration_ms\":${duration_ms:-null}}"
        ;;
    "afterFileEdit")
        escaped_path=$(escape_for_json "$(extract_json_string "file_path" "$input_json")")
        edits=$(extract_json_array "edits" "$input_json")
        event_data="\"event_data\":{\"file_path\":\"$escaped_path\",\"edits\":$edits}"
        ;;
    "beforeShellExecution")
        escaped_cmd=$(escape_for_json "$(truncate_field "$(extract_json_string "command" "$input_json")")")
        escaped_shell=$(escape_for_json "$(extract_json_string "shell" "$input_json")")
        event_data="\"event_data\":{\"command\":\"$escaped_cmd\",\"shell\":\"$escaped_shell\"}"
        ;;
    "afterShellExecution")
        escaped_cmd=$(escape_for_json "$(truncate_field "$(extract_json_string "command" "$input_json")")")
        escaped_shell=$(escape_for_json "$(extract_json_string "shell" "$input_json")")
        exit_code=$(extract_json_number "exit_code" "$input_json")
        escaped_output=$(escape_for_json "$(truncate_field "$(extract_json_string "output" "$input_json")")")
        event_data="\"event_data\":{\"command\":\"$escaped_cmd\",\"shell\":\"$escaped_shell\",\"exit_code\":${exit_code:-null},\"output\":\"$escaped_output\"}"
        ;;
    *)
        event_data="\"event_data\":{}"
        ;;
esac

# Build optional fields (escape all values)
optional_fields=""
[[ -n "$conversation_id" ]] && optional_fields="$optional_fields,\"conversation_id\":\"$(escape_for_json "$conversation_id")\""
[[ -n "$generation_id" ]] && optional_fields="$optional_fields,\"generation_id\":\"$(escape_for_json "$generation_id")\""
[[ -n "$model" ]] && optional_fields="$optional_fields,\"model\":\"$(escape_for_json "$model")\""
[[ -n "$cursor_version" ]] && optional_fields="$optional_fields,\"cursor_version\":\"$(escape_for_json "$cursor_version")\""
workspace_roots=$(extract_json_array "workspace_roots" "$input_json")
[[ "$workspace_roots" != "[]" ]] && optional_fields="$optional_fields,\"workspace_roots\":$workspace_roots"

# Write log entry if logging is enabled
if [[ "$cursor_logging_enabled" == "true" ]]; then
    log_data="{\"user_id\":\"$escaped_user_id\",\"action_type\":\"cursor_$hook_event\",\"timestamp\":$unix_ts,\"success\":true,\"client_id\":\"cursor\"$optional_fields,$event_data}"
    echo "$ts - user_actions - INFO - $log_data" >> "$log_file"
fi

# Trigger background log pusher if there are completed logs
if ls "$LOG_DIR"/*.log.complete 1> /dev/null 2>&1; then
    nohup /usr/local/bin/mcp-gateway-push-logs >/dev/null 2>&1 &
fi

# For beforeSubmitPrompt, must return continue response
[[ "$hook_event" == "beforeSubmitPrompt" ]] && echo '{"continue":true}'
exit 0
