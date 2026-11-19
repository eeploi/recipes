# 0. apt retries: a mirror or package server that drops a connection gets five more tries.
STEP='0. apt retries'
echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-eeploi-retries
