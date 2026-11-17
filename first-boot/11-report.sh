# 11. Tell eeploi the host keys, so it pins them before its first login. eeploi closes port 22
#     itself, once it logs in on the new port (ConnectNewServer).
STEP='11. Report'
curl -fsS --max-time 20 --retry 5 --retry-all-errors --data-urlencode "host_keys=$(cat /etc/ssh/ssh_host_*_key.pub)" "$REPORT_URL"
