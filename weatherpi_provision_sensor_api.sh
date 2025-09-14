#!/bin/bash
# Rerunnable install script for FastAPI sensor backend (using weatherpi_venv)

set -e

APP_DIR="/home/raspi/sensor_api"
VENV="/home/raspi/weatherpi_venv"
LOG_FILE="$APP_DIR/fastapi.log"

echo "[Provision] Ensuring app directory exists..."
mkdir -p "$APP_DIR"
cd "$APP_DIR"

echo "[Provision] Writing source files..."

# main.py
cat > main.py <<'EOF'
from fastapi import FastAPI, Query
from fastapi.responses import JSONResponse
from models import SensorResponse
from queries import build_query, get_window
from db import get_pool
import logging

app = FastAPI()
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

@app.on_event("startup")
async def startup():
    app.state.db = await get_pool()
    logging.info("DB pool established.")

@app.on_event("shutdown")
async def shutdown():
    await app.state.db.close()
    logging.info("DB pool closed.")

@app.get("/temperature", response_model=SensorResponse)
async def get_hourly(device_name: str = Query(None)):
    start, now = get_window(hours=1)
    query = build_query(hours=1, device_name=device_name)
    params = [start] if not device_name else [start, device_name]

    async with app.state.db.acquire() as conn:
        rows = await conn.fetch(query, *params)

    data = [
        {
            "timestamp": r["timestamp"].isoformat(),
            "device_name": r["device_name"],
            "temperature_f": r["temperature_f"],
            "humidity_percent": r["humidity_percent"]
        }
        for r in rows
    ]
    return JSONResponse(content={"data": data, "queried_at": now.isoformat()}, headers={"Cache-Control": "no-store"})

@app.get("/temperature_7d", response_model=SensorResponse)
async def get_7d(device_name: str = Query(None)):
    start, now = get_window(days=7)
    query = build_query(days=7, device_name=device_name)
    params = [start] if not device_name else [start, device_name]

    async with app.state.db.acquire() as conn:
        rows = await conn.fetch(query, *params)

    data = [
        {
            "timestamp": r["timestamp"].isoformat(),
            "device_name": r["device_name"],
            "temperature_f": r["temperature_f"],
            "humidity_percent": r["humidity_percent"]
        }
        for r in rows
    ]
    return JSONResponse(content={"data": data, "queried_at": now.isoformat()}, headers={"Cache-Control": "no-store"})
EOF

# db.py
cat > db.py <<'EOF'
import asyncpg
import logging

DB_CONFIG = {
    "user": "raspi",
    "database": "sensor_data",
    "host": "/var/run/postgresql",
    "port": 5432
}

async def get_pool():
    logging.info("Creating DB pool...")
    return await asyncpg.create_pool(**DB_CONFIG)
EOF

# queries.py
cat > queries.py <<'EOF'
from datetime import datetime, timedelta
import pytz

def build_query(hours=None, days=None, device_name=None):
    base = """
        SELECT timestamp, device_name, temperature_f, humidity_percent
        FROM aht20_sensor_readings
        WHERE timestamp >= $1
    """
    if device_name:
        base += " AND device_name = $2"
    base += " ORDER BY timestamp ASC"
    return base

def get_window(hours=None, days=None):
    local_tz = pytz.timezone("America/Detroit")
    now = datetime.now(local_tz)
    start = now - timedelta(hours=hours) if hours else now - timedelta(days=days)
    return start, now

EOF

# models.py
cat > models.py <<'EOF'
from pydantic import BaseModel
from typing import List

class SensorRecord(BaseModel):
    timestamp: str
    device_name: str
    temperature_f: float
    humidity_percent: float

class SensorResponse(BaseModel):
    data: List[SensorRecord]
    queried_at: str
EOF

# reset.sh
cat > reset.sh <<EOF
#!/bin/bash
APP_DIR="/home/raspi/sensor_api"
VENV="/home/raspi/weatherpi_venv"

echo "[Reset] Stopping FastAPI..."
pkill -f "uvicorn main:app" || echo "No running service found."

echo "[Reset] Clearing logs..."
rm -f "\$APP_DIR/fastapi.log"

echo "[Reset] Restarting FastAPI..."
sudo -u raspi nohup "\$VENV/bin/uvicorn" "\$APP_DIR/main:app" --host 0.0.0.0 --port 8000 > "\$APP_DIR/fastapi.log" 2>&1 &
echo "[Reset] Service restarted at \$(date -u)"
EOF
chmod +x reset.sh

echo "[Provision] Activating weatherpi_venv..."
source "$VENV/bin/activate"

echo "[Provision] Installing/updating dependencies..."
pip install --upgrade fastapi uvicorn asyncpg

echo "[Provision] Restarting FastAPI service..."
./reset.sh

echo "[Provision] ✅ Sensor API is live at http://192.168.9.107:8000"
