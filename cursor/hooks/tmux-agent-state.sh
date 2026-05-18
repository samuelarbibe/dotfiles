#!/bin/bash
# Cursor → tmux-agent-indicator bridge
# Maps Cursor hook events to agent-state transitions.

AGENT_STATE_SCRIPT="$HOME/.tmux/plugins/tmux-agent-indicator/scripts/agent-state.sh"

input=$(cat)

hook_event=""
if [[ "$input" =~ \"hook_event_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    hook_event="${BASH_REMATCH[1]}"
fi

[[ -z "$hook_event" ]] && exit 0
[[ ! -x "$AGENT_STATE_SCRIPT" ]] && exit 0

# Cursor hooks don't inherit $TMUX; find the socket so agent-state.sh works.
if [[ -z "${TMUX:-}" ]]; then
    sock=$(find /tmp/tmux-$(id -u) -name "default" 2>/dev/null | head -1)
    [[ -n "$sock" ]] && export TMUX="$sock,0,0"
fi

case "$hook_event" in
    beforeSubmitPrompt)
        "$AGENT_STATE_SCRIPT" --agent cursor --state running
        echo '{"continue":true}'
        ;;
    stop)
        "$AGENT_STATE_SCRIPT" --agent cursor --state done
        ;;
esac

exit 0
