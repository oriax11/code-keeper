#!/usr/bin/env bash
set -euo pipefail

VENV="$HOME/venvs/ansible"

echo "Creating Ansible virtual environment..."
python3 -m venv "$VENV"

echo "Activating virtual environment..."
source "$VENV/bin/activate"

echo "Upgrading pip..."
python -m pip install --upgrade pip

echo "Installing Ansible..."
python -m pip install ansible

echo
echo "Ansible installed successfully:"
ansible --version

echo
echo "To activate it later, run:"
echo "source $VENV/bin/activate"
