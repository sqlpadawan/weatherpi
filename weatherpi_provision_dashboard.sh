#!/bin/bash
# Rerunnable install script for WeatherPi frontend dashboard

set -e

DASH_DIR="/home/raspi/sensor_dashboard"
echo "[Dashboard] Creating dashboard directory at $DASH_DIR..."
mkdir -p "$DASH_DIR"
cd "$DASH_DIR"

echo "[Dashboard] Writing index.html..."
cat > index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>WeatherPi Dashboard</title>
  <link rel="stylesheet" href="style.css">
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
  <h1>🌡️ WeatherPi Sensor Dashboard</h1>
  <div id="status">Initializing...</div>

  <section>
    <h2>Last Hour</h2>
    <canvas id="chartHour"></canvas>
  </section>

  <section>
    <h2>Last 7 Days</h2>
    <canvas id="chart7d"></canvas>
  </section>

  <script src="script.js"></script>
</body>
</html>
EOF

echo "[Dashboard] Writing style.css..."
cat > style.css <<'EOF'
body {
  font-family: sans-serif;
  margin: 2em;
}
canvas {
  max-width: 100%;
  height: 400px;
}
#status {
  font-size: 0.9em;
  color: gray;
  margin-bottom: 1em;
}
section {
  margin-bottom: 3em;
}
EOF

echo "[Dashboard] Writing script.js..."
cat > script.js <<'EOF'
const statusEl = document.getElementById("status");

const chartHour = new Chart(document.getElementById("chartHour"), {
  type: "line",
  data: { labels: [], datasets: [{ label: "Temp (°F)", data: [], borderColor: "#0077cc", backgroundColor: "rgba(0,119,204,0.2)", fill: true, tension: 0.3 }] },
  options: {
    scales: {
      x: { type: "time", time: { unit: "minute" }, title: { display: true, text: "Time (UTC)" } },
      y: { title: { display: true, text: "Temperature (°F)" } }
    },
    plugins: { legend: { display: true }, tooltip: { mode: "index", intersect: false } },
    responsive: true
  }
});

const chart7d = new Chart(document.getElementById("chart7d"), {
  type: "line",
  data: { labels: [], datasets: [{ label: "Temp (°F)", data: [], borderColor: "#cc3300", backgroundColor: "rgba(204,51,0,0.2)", fill: true, tension: 0.3 }] },
  options: {
    scales: {
      x: { type: "time", time: { unit: "day" }, title: { display: true, text: "Date (UTC)" } },
      y: { title: { display: true, text: "Temperature (°F)" } }
    },
    plugins: { legend: { display: true }, tooltip: { mode: "index", intersect: false } },
    responsive: true
  }
});

async function fetchAndUpdate(endpoint, chart) {
  const ts = new Date().toISOString();
  try {
    const res = await fetch(`${endpoint}?_=${ts}`, { cache: "no-store" });
    const json = await res.json();
    const data = json.data || [];

    chart.data.labels = data.map(d => d.timestamp);
    chart.data.datasets[0].data = data.map(d => d.temperature_f);
    chart.update();

    statusEl.textContent = `Last updated: ${json.queried_at}`;
  } catch (err) {
    console.error(`Error fetching ${endpoint}:`, err);
    statusEl.textContent = `Error fetching data from ${endpoint}`;
  }
}

function updateAll() {
  fetchAndUpdate("/temperature", chartHour);
  fetchAndUpdate("/temperature_7d", chart7d);
}

updateAll();
setInterval(updateAll, 60000); // poll every 60s
EOF

echo "[Dashboard] ✅ Frontend files installed at $DASH_DIR"