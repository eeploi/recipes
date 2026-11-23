# apt retries a dropped connection five times and waits ten minutes for dpkg's lock.
apt-config dump | grep -x 'Acquire::Retries "5";' >/dev/null # not -q: under pipefail, grep stopping early fails apt-config
apt-config dump | grep -x 'DPkg::Lock::Timeout "600";' >/dev/null
