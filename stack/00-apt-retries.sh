# 0. apt retries: a mirror or package server that drops a connection gets five more tries, and an
#    install or upgrade waits up to five minutes for dpkg's lock, which apt's timers can hold.
STEP='0. apt retries'
printf '%s\n' 'Acquire::Retries "5";' 'DPkg::Lock::Timeout "300";' > /etc/apt/apt.conf.d/80-eeploi-retries
