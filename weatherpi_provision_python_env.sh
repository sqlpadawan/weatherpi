#!/bin/bash
set -euo pipefail

## Usage:
# Default setup
#./setup_weatherpi.sh
# Custom venv location and log file
#./setup_weatherpi.sh --venv-dir /opt/weatherpi --log-file /var/log/weatherpi.log
# Add extra packages
#./setup_weatherpi.sh --requirement adafruit-blinka --requirement RPi.GPIO

# 🧩 Default config
DEFAULT_VENV_DIR="$HOME/weatherpi"
DEFAULT_REQUIREMENTS=("adafruit-circuitpython-ahtx0")
DEFAULT_LOG_FILE="$HOME/weatherpi_setup.log"

# 🧵 Parse arguments or use env vars
VENV_DIR="${VENV_DIR:-$DEFAULT_VENV_DIR}"
LOG_FILE="${LOG_FILE:-$DEFAULT_LOG_FILE}"
REQUIREMENTS=("${REQUIREMENTS[@]:-${DEFAULT_REQUIREMENTS[@]}}")

# 🧪 Argument parsing (optional override via flags)
while [[ $# -gt 0 ]]; do
    case "$1" in
        --venv-dir)
            VENV_DIR="$2"
            shift 2
            ;;
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        --requirement)
            REQUIREMENTS+=("$2")
            shift 2
            ;;
        *)
            echo "Unknown option: $1" | tee -a "$LOG_FILE"
            exit 1
            ;;
    esac
done

# 📦 Ensure Python 3 and venv are available
command -v python3 >/dev/null || { echo "Python3 not found. Aborting." | tee -a "$LOG_FILE"; exit 1; }
python3 -m venv --help >/dev/null || { echo "Python venv module missing. Aborting." | tee -a "$LOG_FILE"; exit 1; }

# 🧪 Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment at $VENV_DIR..." | tee -a "$LOG_FILE"
    python3 -m venv "$VENV_DIR"
else
    echo "Virtual environment already exists at $VENV_DIR." | tee -a "$LOG_FILE"
fi

# 🧼 Activate and upgrade pip
source "$VENV_DIR/bin/activate"
echo "Upgrading pip..." | tee -a "$LOG_FILE"
pip install --upgrade pip

# 📥 Install required packages
for pkg in "${REQUIREMENTS[@]}"; do
    echo "Installing $pkg..." | tee -a "$LOG_FILE"
    pip install "$pkg"
done

echo "✅ Setup complete. Virtual environment: $VENV_DIR" | tee -a "$LOG_FILE"