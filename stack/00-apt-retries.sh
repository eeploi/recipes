# 0. apt retries: a dropped connection gets five more tries; dpkg's lock, ten minutes.
STEP='0. apt retries'
printf '%s\n' 'Acquire::Retries "5";' 'DPkg::Lock::Timeout "600";' > /etc/apt/apt.conf.d/80-eeploi-retries
