#!/bin/bash

# Attach a web terminal connection to the shared tmux session.
#
# ttyd runs this for every WebSocket connection and hangs it up when the
# connection closes. The first connection starts the session running the
# launch command; later ones (a refresh, an ingress reconnect, another tab)
# attach to the same session, so whatever is running survives.

session="claude"
launch_command="${1:?usage: attach-session.sh <launch command>}"
replay_lines=1000
last_screen="/tmp/claude-terminal-last-screen"

if tmux has-session -t "=${session}" 2>/dev/null; then
    # tmux only redraws the visible screen on attach. Replay recent history
    # first so earlier output is back in the browser's own scrollback, then
    # push it above the viewport so the redraw does not overwrite it.
    tmux capture-pane -p -e -J -S "-${replay_lines}" -E -1 -t "=${session}:" 2>/dev/null || true
    printf '\033[0m'
    rows=$(stty size 2>/dev/null | cut -d' ' -f1)
    printf '\n%.0s' $(seq "${rows:-24}")
fi

# tmux clears the screen when the session ends, which would hide what the
# program printed last (such as Claude's hint for resuming the conversation).
# Save the final screen from inside the session and show it again afterwards.
session_command="${launch_command}; tmux capture-pane -p -e -J > ${last_screen}"
attached_at=$(mktemp)

tmux -f /opt/tmux.conf new-session -A -s "$session" bash -c "$session_command"

if [ "$last_screen" -nt "$attached_at" ]; then
    # Drop trailing blank rows so the screen ends at its last output.
    awk 'NF { for (; blank; blank--) print ""; print; next } { blank++ }' "$last_screen"

    # ttyd closes the connection as soon as this script exits and drops
    # output it has not sent yet. Ask the terminal for its cursor position and
    # wait for the answer: it comes back only after the browser has received
    # everything printed before the question.
    if saved_tty=$(stty -g 2>/dev/null); then
        stty -echo -icanon
        printf '\033[6n'
        IFS= read -r -s -d R -t 2 _ || true
        stty "$saved_tty"
    fi
fi
rm -f "$attached_at"
