#!/usr/bin/env bash
set -euo pipefail

# === Configurable Parameters ===
#PG_VERSION="${PG_VERSION:-15}"
#PG_USER="${PG_USER:-raspi}"
#PG_DATA_DIR="${PG_DATA_DIR:-/var/lib/postgresql/${PG_VERSION}/main}"

## Usage:
## chmod +x weatherpi_postgresql_provision.sh
## sudo ./weatherpi_postgresql_provision.sh 15 raspi /var/lib/postgresql/15/main 
## sudo ./weatherpi_postgresql_provision.sh --reset

LOG_FILE="/var/log/weatherpi_postgresql_provision.log"

# === Logging Function ===
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

reset_postgres() {
    log "=== PostgreSQL Reset Started ==="
    
    # Debug: Show what packages are currently installed
    log "DEBUG: Checking for PostgreSQL installations..."
    dpkg -l 2>/dev/null | grep postgresql || log "DEBUG: No postgresql packages found in dpkg -l"

    # Check if any PostgreSQL packages are installed using multiple methods
    postgres_installed=false
    
    # Method 1: Check with dpkg -l for installed packages (ii status)
    if dpkg -l 2>/dev/null | grep -q "^ii.*postgresql"; then
        postgres_installed=true
        log "PostgreSQL detected via dpkg -l"
    fi
    
    # Method 2: Use dpkg-query to check specific common postgresql packages
    for pkg in postgresql postgresql-client postgresql-common postgresql-server-dev-all postgresql-contrib; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            postgres_installed=true
            log "PostgreSQL package '$pkg' detected via dpkg-query"
            break
        fi
    done
    
    # Method 3: Check for postgresql binaries in common locations
    if command -v psql >/dev/null 2>&1 || command -v postgres >/dev/null 2>&1 || [ -f /usr/bin/psql ] || [ -f /usr/lib/postgresql/*/bin/postgres ]; then
        postgres_installed=true
        log "PostgreSQL binaries detected in system PATH or common locations"
    fi
    
    # Method 4: Check for postgresql data directories
    if [ -d /var/lib/postgresql ] || [ -d /etc/postgresql ]; then
        postgres_installed=true
        log "PostgreSQL directories detected"
    fi
    
    # Method 5: Check if postgresql service exists
    if systemctl list-unit-files 2>/dev/null | grep -q postgresql || [ -f /etc/systemd/system/postgresql.service ] || [ -f /lib/systemd/system/postgresql.service ]; then
        postgres_installed=true
        log "PostgreSQL service detected"
    fi
    
    if [ "$postgres_installed" = true ]; then
        log "PostgreSQL is installed. Proceeding with reset..."

        # Stop PostgreSQL service if it's running
        if systemctl is-active --quiet postgresql 2>/dev/null; then
            log "PostgreSQL service is running. Stopping it..."
            sudo systemctl stop postgresql
        else
            log "PostgreSQL service is not running or not found."
        fi

        # Also try to stop specific version services
        sudo systemctl stop postgresql@*.service 2>/dev/null || true

        # Get list of all postgresql packages to remove
        log "Identifying PostgreSQL packages to remove..."
        packages_to_remove=$(dpkg -l 2>/dev/null | grep postgresql | awk '{print $2}' | tr '\n' ' ')
        if [ -n "$packages_to_remove" ]; then
            log "Found packages: $packages_to_remove"
        fi

        # Remove PostgreSQL packages (non-interactive)
        log "Removing PostgreSQL packages..."
        export DEBIAN_FRONTEND=noninteractive
        if [ -n "$packages_to_remove" ]; then
            sudo -E apt-get --purge -y remove $packages_to_remove 2>/dev/null || true
        else
            sudo -E apt-get --purge -y remove postgresql* postgresql-client* postgresql-common* postgresql-contrib* 2>/dev/null || true
        fi
        
        # Also use dpkg to force removal of any remaining packages
        remaining_packages=$(dpkg -l 2>/dev/null | grep postgresql | awk '{print $2}' | tr '\n' ' ')
        if [ -n "$remaining_packages" ]; then
            log "Force removing remaining packages: $remaining_packages"
            sudo dpkg --remove --force-remove-reinstreq $remaining_packages 2>/dev/null || true
            sudo dpkg --purge --force-remove-reinstreq $remaining_packages 2>/dev/null || true
        fi
        
        # Clean up residual configuration
        sudo -E apt-get -y autoremove 2>/dev/null || true
        sudo -E apt-get -y autoclean 2>/dev/null || true

        # Remove data directories and logs
        log "Removing PostgreSQL data and configuration..."
        sudo rm -rf /var/lib/postgresql/
        sudo rm -rf /var/log/postgresql/
        sudo rm -rf /etc/postgresql/
        sudo rm -rf /etc/postgresql-common/
        
        # Remove postgres user if it exists
        if id "postgres" &>/dev/null; then
            log "Removing 'postgres' user..."
            sudo deluser --remove-home --quiet postgres 2>/dev/null || true
            log "Removed 'postgres' user."
        fi

        # Remove postgres group if it exists
        if getent group postgres &>/dev/null; then
            log "Removing 'postgres' group..."
            sudo delgroup --quiet postgres 2>/dev/null || true
        fi

    else
        log "PostgreSQL is not installed. Nothing to reset."
    fi

    log "=== PostgreSQL Reset Completed ==="
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
        checksum_status=$(sudo -u postgres "/usr/lib/postgresql/$PG_VERSION/bin/pg_controldata" "$PG_DATA_DIR" | grep "Data page checksum version" || echo "missing")

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

    #sudo -u "$PG_USER" pg_controldata "$PG_DATA_DIR" | grep "Data page checksum version" | tee -a "$LOG_FILE"
    sudo -u postgres "/usr/lib/postgresql/$PG_VERSION/bin/pg_controldata" "$PG_DATA_DIR" | grep "Data page checksum version" | tee -a "$LOG_FILE"

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

### Parse arguments
# Handle reset mode
if [[ $# -eq 1 && "$1" == "--reset" ]]; then
  reset_postgres
fi

# Validate argument count for provisioning
if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <PG_VERSION> <PG_USER> <PG_DATA_DIR> or $0 --reset"
  exit 1
fi

PG_VERSION="$1"
PG_USER="$2"
PG_DATA_DIR="$3"

# === Main Execution ===
log "=== PostgreSQL Setup Started ==="
add_pg_repo
install_postgres
provision_pg_with_checksums
configure_authentication
ensure_running
log "=== PostgreSQL Setup Completed ==="