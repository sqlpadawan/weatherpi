#!/usr/bin/env python3

import board
import busio
import adafruit_ahtx0
import psycopg2
import logging
import socket
from datetime import datetime

# ── Logging Setup ─────────────────────────────────────────────
LOG_FILE = "/home/raspi/ahtx0.log"
logging.basicConfig(
    filename=LOG_FILE,
    level=logging.ERROR,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

# ── Device Identity ───────────────────────────────────────────
device_name = socket.gethostname()

# ── Sensor Setup ─────────────────────────────────────────────
try:
    i2c = busio.I2C(board.SCL, board.SDA)
    #i2c = busio.I2C()
    sensor = adafruit_ahtx0.AHTx0(i2c)
except Exception as e:
    logging.error(f"Sensor initialization failed: {e}")
    exit(1)

# ── Read and Convert ─────────────────────────────────────────
try:
    temperature_c = sensor.temperature
    temperature_f = temperature_c * 9 / 5 + 32
    humidity = sensor.relative_humidity
except Exception as e:
    logging.error(f"Sensor read failed: {e}")
    exit(1)

# ── Insert into PostgreSQL ───────────────────────────────────
try:
    conn = psycopg2.connect(dbname="sensor_data", user="raspi")
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO aht20_sensor_readings (temperature_f, humidity_percent, device_name)
        VALUES (%s, %s, %s);
    """, (temperature_f, humidity, device_name))
    conn.commit()
    cur.close()
    conn.close()
except Exception as e:
    logging.error(f"Database insert failed: {e}")
    exit(1)
