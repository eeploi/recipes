#!/usr/bin/env bash
# Prints what the provider's image brought, one fact per line, so eeploi can record it per server
# and see when a provider changes its image. Reads only. A key may repeat. Run as root.
set -euo pipefail

echo 'fingerprint 1'
echo "kernel $(uname -r)"
# In kB, 0 for none.
echo "swap $(awk '$1 == "SwapTotal:" { print $2 }' /proc/meminfo)"

# cloud-init's name for where the server came from, such as nocloud or a provider.
datasource=$(cloud-id 2>/dev/null) || datasource=none
echo "cloud-init-datasource $datasource"

# The users with a login the image created: a regular UID, not the deploy user eeploi made.
deploy=$(sed -n 's/^DEPLOY_USER=//p' /etc/eeploi/recipes.conf 2>/dev/null) || deploy=''
awk -F: -v deploy="$deploy" '$3 >= 1000 && $3 < 65534 && $1 != deploy && $7 !~ /(nologin|false)$/ { print "default-user " $1; n++ }
  END { if (!n) print "default-user none" }' /etc/passwd

# Each apt source, as its URI, in the one-line and the deb822 format.
{
  grep -hsE '^deb(-src)?[[:space:]]' /etc/apt/sources.list /etc/apt/sources.list.d/*.list | sed -E 's/\[[^]]*\]//' | awk '{ print $2 }' || true
  grep -hs '^URIs:' /etc/apt/sources.list.d/*.sources | awk '{ for (i = 2; i <= NF; i++) print $i }' || true
} | LC_ALL=C sort -u | sed 's/^/apt-mirror /'

# A provider's agent, as a package or a snap.
for name in amazon-ssm-agent do-agent droplet-agent google-guest-agent hc-utils open-vm-tools oracle-cloud-agent qemu-guest-agent walinuxagent; do
  if [ "$(dpkg-query -W -f '${db:Status-Status}' "$name" 2>/dev/null)" = installed ] || [ -d "/snap/$name" ]; then
    echo "agent $name"
  fi
done
