# apt retries a dropped connection five times.
apt-config dump | grep -x 'Acquire::Retries "5";' >/dev/null # not -q: under pipefail, grep stopping early fails apt-config
