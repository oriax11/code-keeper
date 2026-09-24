#!/bin/bash
set -euo pipefail

# Install Docker in rootless mode for the current user (no sudo required).
# Prerequisites: curl, uidmap (newuidmap/newgidmap) must already be on the system.
# See: https://docs.docker.com/engine/security/rootless/

DOCKER_VERSION="${DOCKER_VERSION:-27.5.1}"
INSTALL_DIR="$HOME/bin"

# --- Preflight checks ---

if command -v dockerd-rootless-setuptool.sh &>/dev/null; then
    echo "Docker rootless already appears to be installed."
    exit 0
fi

if ! command -v curl &>/dev/null; then
    echo "Error: curl is required but not found." >&2
    exit 1
fi

if ! command -v newuidmap &>/dev/null || ! command -v newgidmap &>/dev/null; then
    echo "Error: uidmap (newuidmap/newgidmap) is required but not found." >&2
    echo "Ask your system administrator to install the 'uidmap' package." >&2
    exit 1
fi

# --- Download and extract Docker binaries ---

mkdir -p "$INSTALL_DIR"

echo "Downloading Docker ${DOCKER_VERSION} static binaries..."
curl -fsSL "https://download.docker.com/linux/static/stable/$(uname -m)/docker-${DOCKER_VERSION}.tgz" \
    -o "/tmp/docker-${DOCKER_VERSION}.tgz"

echo "Extracting to ${INSTALL_DIR}..."
tar xzf "/tmp/docker-${DOCKER_VERSION}.tgz" --strip-components=1 -C "$INSTALL_DIR"
rm -f "/tmp/docker-${DOCKER_VERSION}.tgz"

# --- Download rootless extras ---

echo "Downloading Docker rootless extras..."
curl -fsSL "https://download.docker.com/linux/static/stable/$(uname -m)/docker-rootless-extras-${DOCKER_VERSION}.tgz" \
    -o "/tmp/docker-rootless-extras-${DOCKER_VERSION}.tgz"

tar xzf "/tmp/docker-rootless-extras-${DOCKER_VERSION}.tgz" --strip-components=1 -C "$INSTALL_DIR"
rm -f "/tmp/docker-rootless-extras-${DOCKER_VERSION}.tgz"

# --- Verify binaries were extracted ---

if [ ! -f "$INSTALL_DIR/dockerd-rootless-setuptool.sh" ]; then
    echo "Error: dockerd-rootless-setuptool.sh not found in $INSTALL_DIR" >&2
    echo "Listing contents of $INSTALL_DIR:" >&2
    ls -la "$INSTALL_DIR" >&2
    exit 1
fi

chmod +x "$INSTALL_DIR"/dockerd-rootless*.sh

# --- Ensure ~/bin is in PATH ---

export PATH="$INSTALL_DIR:$PATH"

# --- Run rootless setup ---

echo "Running rootless setup..."
"$INSTALL_DIR/dockerd-rootless-setuptool.sh" install

# --- Persist environment in .zshrc ---

MARKER="# docker-rootless"
if ! grep -qF "$MARKER" "$HOME/.zshrc" 2>/dev/null; then
    {
        echo ""
        echo "$MARKER"
        echo 'export PATH="$HOME/bin:$PATH"'
        echo 'export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/docker.sock"'
    } >> "$HOME/.zshrc"
fi

echo ""
echo "Docker rootless installed successfully."
echo "Run 'source ~/.zshrc' or open a new shell to use it."
echo "Verify with: docker run --rm hello-world"
