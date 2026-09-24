#!/bin/bash
# Start the rootless Docker daemon so it survives this shell session.
# If the daemon is already running, this is a no-op.

export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/docker.sock"
SOCKET="${XDG_RUNTIME_DIR}/docker.sock"

# Already running?
if [ -S "$SOCKET" ] && docker info >/dev/null 2>&1; then
    echo "Docker daemon already running at $SOCKET"
    exit 0
fi

# No lingering daemon from a previous session.
pkill -f dockerd-rootless.sh 2>/dev/null || true
sleep 1

echo "Starting rootless Docker daemon (detached)..."
nohup dockerd-rootless.sh > /tmp/rootless-dockerd.log 2>&1 &
disown

# Wait up to 30s for the socket to appear.
for i in $(seq 1 30); do
    if [ -S "$SOCKET" ]; then
        break
    fi
    sleep 1
done

if [ ! -S "$SOCKET" ]; then
    echo "Error: Docker socket not found at $SOCKET" >&2
    echo "Check /tmp/rootless-dockerd.log" >&2
    exit 1
fi

echo "Docker daemon up: $DOCKER_HOST"