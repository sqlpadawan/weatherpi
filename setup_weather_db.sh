#!/bin/bash

# Move to a safe directory to avoid permission warnings
cd /tmp

DB_NAME="sensor_data"
RASPI_USER="raspi"

# Check if database exists
DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'")

# Create database if it doesn't exist
if [ "$DB_EXISTS" != "1" ]; then
  echo "📦 Creating database '$DB_NAME'..."
  sudo -u postgres createdb $DB_NAME
else
  echo "✅ Database '$DB_NAME' already exists."
fi

# Create table and grant permissions to raspi
echo "🧱 Creating table 'aht20_sensor_readings' and granting access to '$RASPI_USER'..."
sudo -u postgres psql -d $DB_NAME <<EOF
CREATE TABLE IF NOT EXISTS aht20_sensor_readings (
   id SERIAL PRIMARY KEY,
   timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
   temperature_f REAL NOT NULL,
   humidity_percent REAL NOT NULL,
   device_name TEXT NOT NULL
);

-- Create raspi role if it doesn't exist
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$RASPI_USER') THEN
    CREATE ROLE $RASPI_USER LOGIN;
  END IF;
END
\$\$;

-- Grant privileges
GRANT CONNECT ON DATABASE $DB_NAME TO $RASPI_USER;
GRANT USAGE ON SCHEMA public TO $RASPI_USER;
GRANT SELECT, INSERT ON aht20_sensor_readings TO $RASPI_USER;
EOF

echo "🎉 Setup complete: '$DB_NAME' with table 'aht20_sensor_readings'. Access granted to '$RASPI_USER'."