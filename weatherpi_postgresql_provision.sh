#!/usr/bin/env bash
set -euo pipefail

# 🔧 Configurable variables
DB_USER="sensorlogger"
DB_NAME="sensordata"
LOG_FILE="/var/log/postgresql_setup.log"

# 🧭 Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $*" | tee -a "$LOG_FILE"
}

# 🧭 Safe PostgreSQL command executor
psql_exec() {
    sudo -u postgres -- bash -c "cd ~postgres && psql -c \"$1\""
}

# 🔁 Reset logic
reset_postgresql() {
    log "Resetting PostgreSQL state..."

    # Drop DB and role if they exist
    psql_exec "DROP DATABASE IF EXISTS ${DB_NAME};"
    psql_exec "DROP ROLE IF EXISTS ${DB_USER};"

    # Remove Linux user
    if id "${DB_USER}" &> /dev/null; then
        sudo deluser --remove-home "${DB_USER}" || true
        log "Linux user '${DB_USER}' removed."
    fi

    # Remove log file
    sudo rm -f "$LOG_FILE"
    log "Log file removed."

    log "Reset complete. Ready to re-provision."
    exit 0
}

# 🧩 Install PostgreSQL if missing
install_postgresql() {
    if ! command -v psql &> /dev/null; then
        log "PostgreSQL not found. Installing..."
        sudo apt update
        sudo apt install -y postgresql postgresql-contrib
        log "PostgreSQL installed."
    else
        log "PostgreSQL already installed."
    fi
}

# 🔐 Ensure PostgreSQL service is running
ensure_service() {
    if ! systemctl is-active --quiet postgresql; then
        log "Starting PostgreSQL service..."
        sudo systemctl start postgresql
    fi
}

# 👤 Create Linux and PostgreSQL user if missing
create_user_and_role() {
    if ! id "$DB_USER" &> /dev/null; then
        log "Creating Linux user '$DB_USER'..."
        sudo useradd -m -s /bin/bash "$DB_USER"
    fi

    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1; then
        log "Creating PostgreSQL role '$DB_USER' with peer auth..."
        psql_exec "CREATE ROLE ${DB_USER} WITH LOGIN;"
    else
        log "PostgreSQL role '$DB_USER' already exists."
    fi
}

# 🗃️ Create database if missing
create_database() {
    if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "${DB_NAME}"; then
        log "Creating database '${DB_NAME}' owned by '${DB_USER}'..."
        sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
    else
        log "Database '${DB_NAME}' already exists."
    fi
}

# 🔧 Grant privileges (idempotent)
grant_privileges() {
    log "Ensuring privileges on '${DB_NAME}' for '${DB_USER}'..."
    psql_exec "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
}

# 🚀 Main execution
main() {
    log "Starting PostgreSQL setup..."
    install_postgresql
    ensure_service
    create_user_and_role
    create_database
    grant_privileges
    log "PostgreSQL setup complete."
}

# 🧭 Entry point
if [[ "${1:-}" == "--reset" ]]; then
    reset_postgresql
else
    main
fi