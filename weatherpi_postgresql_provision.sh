#!/usr/bin/env bash
set -euo pipefail

# === Configurable Parameters ===
#PG_VERSION="${PG_VERSION:-15}"
#PG_USER="${PG_USER:-raspi}"
#PG_DATA_DIR="${PG_DATA_DIR:-/var/lib/postgresql/${PG_VERSION}/main}"
#LOG_FILE="/var/log/postgres_setup.log"

## Usage:
## chmod +x weatherpi_postgresql_provision.sh
## sudo ./weatherpi_postgresql_provision.sh 15 raspi /var/lib/postgresql/15/main /var/log/postgres_setup.log

### Parse arguments
if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <PG_VERSION> <PG_USER> <PG_DATA_DIR> <LOG_FILE>"
  exit 1
fi

PG_VERSION="$1"
PG_USER="$2"
PG_DATA_DIR="$3"
LOG_FILE="$4"

# === Logging Function ===
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# === Check if PostgreSQL is installed ===
is_postgres_installed() {
    command -v psql >/dev/null 2>&1 && psql --version | grep -q "$PG_VERSION"
}

# === Add PostgreSQL APT repo if needed ===
add_pg_repo() {
    if ! grep -q "apt.postgresql.org" /etc/apt/sources.list.d/pgdg.list 2>/dev/null; then
        log "Adding PostgreSQL APT repository..."
        curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
        echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
        sudo apt-get update
    else
        log "PostgreSQL APT repo already present."
    fi
}

# === Install PostgreSQL ===
install_postgres() {
    if is_postgres_installed; then
        log "PostgreSQL $PG_VERSION already installed."
    else
        log "Installing PostgreSQL $PG_VERSION..."
        sudo apt-get install -y "postgresql-$PG_VERSION" "postgresql-client-$PG_VERSION"
    fi
}

# === Provision PostgreSQL with Checksums ===
provision_pg_with_checksums() {
    log "Checking PostgreSQL cluster for checksum status..."

    if [ -d "$PG_DATA_DIR" ]; then
        local checksum_status
        checksum_status=$(sudo -u "$PG_USER" pg_controldata "$PG_DATA_DIR" | grep "Data page checksum version" || echo "missing")

        if echo "$checksum_status" | grep -q "0"; then
            log "Checksums are disabled. Reinitializing cluster with checksums..."
            sudo systemctl stop "postgresql@$PG_VERSION-main" || true
            sudo pg_dropcluster "$PG_VERSION" main --stop
            sudo pg_createcluster "$PG_VERSION" main --start -- --data-checksums
            log "Cluster reinitialized with checksums."
        else
            log "Checksums already enabled or cluster not initialized yet."
        fi
    else
        log "No existing cluster. Initializing with checksums..."
        # Remove stale cluster config if present
        if [ -d "/etc/postgresql/$PG_VERSION/main" ] && ! [ -d "$PG_DATA_DIR" ]; then
            log "Stale cluster config detected without data directory. Removing..."
            sudo pg_dropcluster "$PG_VERSION" main --stop
        fi
        sudo pg_createcluster "$PG_VERSION" main --start -- --data-checksums
        log "Cluster initialized with checksums."
    fi

    sudo -u "$PG_USER" pg_controldata "$PG_DATA_DIR" | grep "Data page checksum version" | tee -a "$LOG_FILE"
}

# === Configure peer authentication ===
configure_authentication() {
    local pg_hba="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
    if grep -q "^local\s\+all\s\+$PG_USER\s\+peer" "$pg_hba"; then
        log "Peer authentication already configured for user '$PG_USER'."
    else
        log "Configuring peer authentication for user '$PG_USER'..."
        sudo sed -i "s/^local\s\+all\s\+all\s\+.*/local all $PG_USER peer/" "$pg_hba"
        sudo systemctl restart "postgresql@$PG_VERSION-main"
    fi
}

# === Ensure PostgreSQL is running ===
ensure_running() {
    if systemctl is-active --quiet "postgresql@$PG_VERSION-main"; then
        log "PostgreSQL service is running."
    else
        log "Starting PostgreSQL service..."
        sudo systemctl start "postgresql@$PG_VERSION-main"
    fi
}

# === Main Execution ===
log "=== PostgreSQL Setup Started ==="
add_pg_repo
install_postgres
provision_pg_with_checksums
configure_authentication
ensure_running
log "=== PostgreSQL Setup Completed ==="