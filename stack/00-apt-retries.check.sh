# apt retries a dropped connection five times.
apt-config dump | grep -qx 'Acquire::Retries "5";'
