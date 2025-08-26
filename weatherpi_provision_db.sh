#!/bin/bash

## Usage:
# Provision: sudo ./weatherpi_provision_db.sh
# Reset:     sudo ./weatherpi_provision_db.sh --reset

cd /tmp

DB_NAME="sensor_data"
RASPI_USER="raspi"

# Handle reset logic
if [[ "$1" == "--reset" ]]; then
  echo "⚠️ Reset mode activated: removing database '$DB_NAME' and role '$RASPI_USER'..."

  # Drop database if it exists
  DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'")
  if [ "$DB_EXISTS" == "1" ]; then
    echo "🗑️ Dropping database '$DB_NAME'..."
    sudo -u postgres dropdb $DB_NAME
  else
    echo "ℹ️ Database '$DB_NAME' does not exist."
  fi

  # Drop user if it exists
  USER_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$RASPI_USER'")
  if [ "$USER_EXISTS" == "1" ]; then
    echo "🗑️ Dropping role '$RASPI_USER'..."
    sudo -u postgres psql -c "DROP ROLE $RASPI_USER;"
  else
    echo "ℹ️ Role '$RASPI_USER' does not exist."
  fi

  echo "✅ Reset complete. Exiting."
  exit 0
fi

# Provisioning logic
DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'")
if [ "$DB_EXISTS" != "1" ]; then
  echo "📦 Creating database '$DB_NAME'..."
  sudo -u postgres createdb $DB_NAME
else
  echo "✅ Database '$DB_NAME' already exists."
fi

echo "🧱 Creating table 'aht20_sensor_readings' and granting access to '$RASPI_USER'..."
sudo -u postgres psql -d $DB_NAME <<EOF
CREATE TABLE IF NOT EXISTS aht20_sensor_readings (
   id SERIAL PRIMARY KEY,
   timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
   temperature_f REAL NOT NULL,
   humidity_percent REAL NOT NULL,
   device_name TEXT NOT NULL
);

DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$RASPI_USER') THEN
    CREATE ROLE $RASPI_USER LOGIN;
  END IF;
END
\$\$;

GRANT CONNECT ON DATABASE $DB_NAME TO $RASPI_USER;
GRANT USAGE ON SCHEMA public TO $RASPI_USER;
GRANT SELECT, INSERT, UPDATE, DELETE ON aht20_sensor_readings TO $RASPI_USER;
GRANT USAGE, SELECT ON SEQUENCE aht20_sensor_readings_id_seq TO $RASPI_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO $RASPI_USER;
EOF

echo "🎉 Setup complete: '$DB_NAME' with table 'aht20_sensor_readings'. Access granted to '$RASPI_USER'."