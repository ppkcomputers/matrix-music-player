#!/bin/bash
CONFIG="/home/ppk/.config/Quickshell/music-player/mkv-stream.qml"

if pgrep -f "$CONFIG" > /dev/null; then
    # Syntax: qs ipc --path <PATH> call <OBJECT> <FUNCTION>
    qs ipc --path "$CONFIG" call mkv-stream toggleVisibility
    echo "Toggled"
else
    qs -p "$CONFIG" &
    echo "Started"
fi
