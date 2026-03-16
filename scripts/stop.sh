#!/usr/bin/env bash
# Stops the background servers started by bootstrap.sh

PIDS_FILE=".pids"

if [[ ! -f "$PIDS_FILE" ]]; then
    echo "No .pids file found — servers may not be running, or were already stopped."
    exit 0
fi

echo "Stopping servers..."

# Read and kill each PID
while IFS='=' read -r key val; do
    # Strip any whitespace
    val="${val//[[:space:]]/}"
    if [[ -n "$val" && "$val" =~ ^[0-9]+$ ]]; then
        if kill "$val" 2>/dev/null; then
            echo "  Stopped $key (PID $val)"
        else
            echo "  $key (PID $val) was already stopped"
        fi
    fi
done < "$PIDS_FILE"

rm -f "$PIDS_FILE"
echo "Done."
