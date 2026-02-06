#!/usr/bin/env bash
# ============================================================================
# AutoLocation - Python environment setup
# ============================================================================
# Usage:
#   chmod +x setup.sh
#   ./setup.sh
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.venv"
REQUIREMENTS="${SCRIPT_DIR}/requirements.txt"

echo "==> Setting up AutoLocation Python environment..."
echo "    Directory: ${SCRIPT_DIR}"

# 1. Create virtual environment
if [ -d "${VENV_DIR}" ]; then
    echo "==> Virtual environment already exists at ${VENV_DIR}, re-using it."
else
    echo "==> Creating virtual environment at ${VENV_DIR}..."
    python3 -m venv "${VENV_DIR}"
fi

# 2. Activate it
echo "==> Activating virtual environment..."
source "${VENV_DIR}/bin/activate"

# 3. Upgrade pip to latest
echo "==> Upgrading pip..."
pip install --upgrade pip --quiet

# 4. Install requirements
echo "==> Installing requirements from ${REQUIREMENTS}..."
pip install -r "${REQUIREMENTS}"

echo ""
echo "==> Setup complete!"
echo "    To activate manually:  source ${VENV_DIR}/bin/activate"
echo "    To run the bridge:     python3 ${SCRIPT_DIR}/bridge.py"
