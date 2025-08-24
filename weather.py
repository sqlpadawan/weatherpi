import time
import board
import adafruit_ahtx0

# Initialize I2C bus and sensor
i2c = board.I2C()
sensor = adafruit_ahtx0.AHTx0(i2c)

# Read and print values
while True:
    celsius = sensor.temperature
    fahrenheit = (celsius * 9 / 5) + 32
    humidity = sensor.relative_humidity
    print(f"Temp: {celsius:.2f} °C / {fahrenheit:.2f} °F | Humidity: {humidity:.2f} %")
    time.sleep(60)
