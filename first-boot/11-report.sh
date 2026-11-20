# 11. Tell eeploi the host keys, so it pins them before its first login. eeploi closes port 22
#     itself, once it logs in on the new port (ConnectNewServer).
STEP='11. Report'
report --data-urlencode "host_keys=$(cat /etc/ssh/ssh_host_*_key.pub)"
