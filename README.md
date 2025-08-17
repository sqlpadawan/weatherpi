ssh -i /mnt/c/Users/sqlpa/.ssh/raspi_key raspi@192.168.9.227

scp -i /mnt/c/Users/sqlpa/.ssh/raspi_key /mnt/c/Users/sqlpa/OneDrive/Temp/weather_pi_provision.sh raspi@192.168.9.227:/home/raspi/

chmod +x weather_pi_provision.sh
sudo ./weatherpi_provision.sh \
  weatherpi02 \
  192.168.9.105 \
  192.168.9.1 \
  192.168.9.1 \
  https://raw.githubusercontent.com/sqlpadawan/raspi_key/main/raspi_key.pub \
  raspi

Make sure /etc/postgresql/*/main/pg_hba.conf includes:

# Allow local connections via peer
local   all             all                                     peer

Then reload PostgreSQL:

sudo systemctl reload postgresql

Testing Peer Auth
sudo -u sensorlogger psql -d sensordata
