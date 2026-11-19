DEPLOY_USER={user}
SSH_PORT={port}
PHP={php}

[ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }
. /etc/os-release; [ "$VERSION_ID" = "{version}" ] || { echo "Ubuntu {version} only, found $VERSION_ID"; exit 1; }
