# Probes

A probe prints the settings in effect for one piece of software, so a report can show how a server is set up without anyone typing commands on it. `ubuntu-26.04/probes` lists them, in the order a report shows them. Each lives next to the step that installs its software, as `NN-name.probe.sh`; its name is the part between `NN-` and `.probe.sh`.

## Format

- **Run:** `bash NN-name.probe.sh`, as root, as the helper runs a check: from `/`, with `env -i`. It takes no values, so it works on a server the steps never set up.
- **Not there:** a probe first looks for its software (its binary). Without it: no lines, exit 0.
- **Read:** what the software itself reads, after every drop-in (`sshd -T`, `nginx -T`, `php-fpm -tt`), not the files one by one. That is the config on disk, not what a running daemon loaded before its last reload (D-17).
- **Output:** one fact per line, `<key> <value>`. The key is one of the probe's own, `a-z`, `0-9`, `_` and `-`; the value is printable text with no space at its end. A key may repeat. A probe prints only what its list holds: never a key, a password, a token, a certificate or a visitor's IP. A value is one line.
- **Failed:** an exit status other than 0. stderr is not part of the output: an error message can quote a config line. A probe whose reading may be out of step with the software's prints nothing and fails, rather than print what it can't place (nginx).
- **`--safe`:** prints the settings whose values are safe to show, one name per line, as the software's config files write them, and runs nothing else. A comparison with what the steps wrote shows a value only for these.

## Probes and their lines

| Probe | File | Reads | Lines |
|---|---|---|---|
| `ssh` | `stack/04-ssh.probe.sh` | `sshd -T` | `<setting> <value>`: port, root and password login, `maxauthtries`, `allowusers`, forwarding, kex, MACs, ciphers, host keys and more |
| `ufw` | `stack/05-ufw.probe.sh` | `ufw status verbose` | `status`, `logging`, `default`, `rule <to> <action> <from>`, without a rule's comment |
| `fail2ban` | `stack/06-fail2ban.probe.sh` | `fail2ban-client` | `running yes\|no`; `jail <name> banned <n> total-banned <n> failed <n> total-failed <n>`, counts only (D-18) |
| `apt` | `stack/07-apt.probe.sh` | `apt-config dump`, `apt-get -s dist-upgrade` | `allowed-origin`, `origin-pattern`, `dpkg-option`, `automatic-reboot`, `periodic-*`; `updates <n>`, `security-updates <n>` and `lists-updated <time>`, from the lists on the server (D-20) |
| `kernel` | `stack/07-kernel.probe.sh` | `/proc/sys`, `modprobe -n -v` | `sysctl <name> <value>` for the settings step 7 sets (with `*`: every interface's values); `module <sctp\|rds\|tipc> <blocked\|loadable\|not-found> <loaded\|not-loaded>` |
| `needrestart` | `stack/07-needrestart.probe.sh` | `needrestart -b -r l` | `kernel <current\|abi-upgrade\|upgrade\|unknown>`, `kernel-running`, `kernel-expected`, `microcode`, `service <unit>` |
| `nginx` | `stack/08-nginx.probe.sh` | `nginx -T` | `server <n> file <path>`, `server <n> listen\|server_name\|ssl_reject_handshake <arguments>`; `http server_tokens\|fastcgi_buffer_size\|fastcgi_buffers\|real_ip_header\|set_real_ip_from <arguments>`; `nginx-conf-dpkg-dist yes\|no`: a newer stock `nginx.conf` waits (D-27) |
| `php-fpm` | `ubuntu-26.04/01-php-fpm.probe.sh` | `php-fpm<v> -tt`, `php-fpm<v> -i` | `pool <v> <pool> <setting> <value>`: user, group, listen and its owner, group and mode, pm, max children and requests; `ini <v> expose_php\|session.upload_progress.enabled\|opcache.validate_permission <value>` |
| `postgresql` | `ubuntu-26.04/01-postgresql.probe.sh` | `postgres -C`, per cluster | `cluster <v>/<name> <setting> <value>`: listen addresses, port, SSL, password encryption, max connections; `cluster <v>/<name> unreadable` for a cluster postgres can't read |
| `mysql` | `ubuntu-26.04/01-mysql.probe.sh` | `mariadbd` or `mysqld --print-defaults` | `option <name> <value>`: bind address, port, networking, `local-infile`, max connections, secure transport, name resolve; `off` for one turned off with `skip-` or `disable-` |
| `redis` | `ubuntu-26.04/01-redis.probe.sh` | `ss`, `redis-cli PING` | `listen <address:port>` or `listen none`; `password yes\|no\|unknown` (D-19) |
| `versions` | `ubuntu-26.04/01-versions.probe.sh` | `dpkg-query`, npm's `package.json`, Composer's phar | `package <name> <version>` for nginx, PHP-FPM, PostgreSQL, MariaDB, MySQL, Redis, Node.js, npm, Composer; `npm <version>` and `composer <version>` for the ones in `/usr/local` |

For example, part of the `ssh` probe's output:

```
port 10022
permitrootlogin no
passwordauthentication no
maxauthtries 3
allowusers deploy
```

Grouped lines carry their group first in the value: the server block's number (`server`), the PHP version and pool (`pool`), the cluster (`cluster`), the jail (`jail`).

## Limits

- [D-16](DECISIONS.md#d-16-probes-one-per-piece-of-software): only the settings a probe lists are shown; a new one is a new release.
- [D-17](DECISIONS.md#d-17-probes-read-the-config-on-disk): the config on disk, not what a running daemon loaded.
- [D-18](DECISIONS.md#d-18-fail2ban-shows-counts-never-addresses): fail2ban counts, never addresses.
- [D-19](DECISIONS.md#d-19-redis-shows-where-it-listens-no-settings): Redis shows where it listens and whether it asks for a password, no settings.
- [D-20](DECISIONS.md#d-20-waiting-updates-as-of-the-last-package-list-update): waiting updates as of the last package list update.
- nginx: a directive from a file included inside a server block, such as a snippet, shows under `http`.
- Redis: any process named `redis-server` counts, so a user on the server can make up its `listen` and `password` lines.
