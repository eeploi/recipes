# Decisions

Choices made on purpose, and the risks and limits accepted with them, so an audit can tell a choice from a mistake.

## For reviewers and audits

- Read this file first.
- A finding against an entry here is not a bug. Report it as "challenges D-n", with an argument the entry doesn't already answer.
- A rejected audit finding becomes a new entry, so the next audit doesn't raise it again.
- Anything that could be a vulnerability, an entry here included, goes through the [security policy](.github/SECURITY.md), not a public issue.

## How entries work

- One entry per decision, numbered `D-1`, `D-2` and so on. A number is never reused or renumbered.
- **Kind** is `decision`, `accepted risk` or `known limit`.
- **Accepted**, when present, names what a decision costs.
- **Decided** gives the date and the issue or pull request in this repo.
- **Where** names the files the entry shapes, if any. The line it shapes carries a comment `# D-n: …`. `bin/check-layout.sh` fails on a `D-n` comment without an entry here, and on a file in **Where** without its comment.
- A changed decision is a new entry. The old one stays, with **Replaced by** `D-n`.
- No private details: no server names, addresses or business reasons. Only what explains the code.

## D-1: Prehashed signatures only

- **Kind:** decision
- **Decided:** 2026-11-21, #18
- **What:** a release manifest's `.minisig` must be a prehashed signature (`ED`, minisign's default). A legacy signature (`Ed`, `minisign -l`) is refused, and every `minisign -V` runs with `-H`.
- **Why:** one signature format on every server and in every check. The helper applies the same rule.
- **Where:** `bin/build-release.sh`, `.github/workflows/ci.yml`

## D-2: Releases are signed in the maintainer's own terminal

- **Kind:** decision
- **Decided:** 2026-11-21, #29
- **What:** `bin/release.sh` signs with `minisign -S -H` in an interactive terminal, where the maintainer types the key's password. CI and scripts never sign. The recipes key is its own, apart from the helper's.
- **Why:** the secret key and its password never sit on a machine or service that runs unattended. Each release needs a person.
- **Where:** `bin/release.sh`

## D-3: SSH keeps local forwarding

- **Kind:** decision
- **Decided:** 2026-11-21, #19 (PR #35)
- **What:** `AllowTcpForwarding local` and `AllowStreamLocalForwarding local`. Remote forwarding, agent and X11 forwarding and tunnels are off.
- **Why:** an SSH tunnel to the database (`ssh -L`) is how a database client reaches it, over TCP or a Unix socket. Nothing else needs forwarding.
- **Where:** `stack/04-ssh.sh`

## D-4: SSH algorithms removed from the defaults; user keys left alone

- **Kind:** decision
- **Decided:** 2026-11-21, #36 (PR #38)
- **What:** sshd offers no NIST curve key exchange, no SHA-1 MAC and no ECDSA host key algorithm. They are removed with the `-` form, so new defaults from Ubuntu's updates still come in. Host keys are ed25519 and RSA. The ECDSA host key file stays on disk. `PubkeyAcceptedAlgorithms` is not narrowed.
- **Why:** the removed algorithms are the ones audits flag. A fixed list would freeze today's choice. Narrowing user keys would lock out working clients for no gain on the server side.
- **Accepted:** OpenSSH clients before 6.5 can't connect.
- **Where:** `stack/04-ssh.sh`

## D-5: Ubuntu's PHP, or another one from packages.sury.org

- **Kind:** decision
- **Decided:** 2026-11-21, #32 (PR #37)
- **What:** PHP 8.5 comes from Ubuntu's archive. Another version (8.3, 8.4 on Ubuntu 26.04) comes from packages.sury.org/php, a fixed source with its signing key pinned. The Launchpad PPA goes.
- **Why:** the PPA has no builds for 26.04, and its rsa1024 key is refused by apt there. sury.org is the same maintainer's archive.
- **Where:** `ubuntu-26.04/php-source.sh`, `ubuntu-26.04/01-packages.sh`

## D-6: Security updates only, and every update of a sury.org PHP

- **Kind:** decision
- **Decided:** 2026-11-22, #22 (PR #49)
- **What:** unattended-upgrades takes Ubuntu's and Ubuntu Pro's security pockets only. A PHP from packages.sury.org gets all its updates.
- **Why:** sury.org has no security channel, and PHP's security fixes come only as point releases.
- **Where:** `stack/07-updates.sh`

## D-7: CI builds PHP 8.5 and 8.4

- **Kind:** decision
- **Decided:** 2026-11-21, PR #37
- **What:** the `server` job builds two servers: 8.5 (Ubuntu's PHP) and 8.4 (sury.org). 8.3 isn't built.
- **Why:** 8.3 and 8.4 take the same path, source and key, so 8.4 stands for both.
- **Where:** `.github/workflows/ci.yml`

## D-8: Lynis and ssh-audit report, never gate

- **Kind:** decision
- **Decided:** 2026-11-21, #26 (PR #34), PR #35
- **What:** CI runs Lynis and ssh-audit on the built server and publishes their output. Neither fails a build.
- **Why:** they find what we missed. Their suggestions become issues, not automatic failures, since some are decided against here.
- **Where:** `.github/workflows/ci.yml`

## D-9: CI pins the helper release and its key

- **Kind:** decision
- **Decided:** 2026-11-21, PR #30
- **What:** CI reads one helper release (`HELPER_TAG`) and checks it with the helper's key, pinned in the workflow, not read next to the release.
- **Why:** a test against a moving or self-vouching helper proves nothing. A new helper release is a reviewed change here.
- **Where:** `.github/workflows/ci.yml`

## D-10: No migration for servers built before a change

- **Kind:** accepted risk
- **Decided:** 2026-11-21, PR #35
- **What:** while eeploi is in development, a changed `first-boot` or `window` step isn't brought to servers built earlier. On such a server, `recipe-run` can end `result failed` on that step's check.
- **Why:** there are no customer servers yet. The failed check shows the server is behind, rather than hiding it.

## D-11: Checks read the config on disk

- **Kind:** known limit
- **Decided:** 2026-11-21, PR #35
- **What:** `sshd -T` and `nginx -t` read the config files, not what the running daemon loaded. A change that isn't reloaded yet passes the check.
- **Why:** neither daemon reports its running config. The steps reload or restart after a change, and a first boot ends with step 10, which starts the services.
- **Where:** `stack/04-ssh.check.sh`, `stack/08-nginx.check.sh`

## D-12: The sury.org key expires 2028-02-04

- **Kind:** known limit
- **Decided:** 2026-11-21, PR #37
- **What:** the pinned key `15058500A0235D97F5D10063B188E2B695BD4743` expires on 2028-02-04. A renewed key needs a new pin, in a new release.
- **Why:** a pinned key is checked byte for byte, so it can't follow a renewal on its own.
- **Where:** `ubuntu-26.04/php-source.sh`

## D-13: A reload nginx takes, then rejects

- **Kind:** known limit
- **Decided:** 2026-11-22, #5 (PR #59)
- **What:** step 8 restores its old config when `nginx -t` or the reload fails. A reload command that succeeds only means nginx got the signal. If nginx then can't apply the config (a port it can't bind, for one), the step still reports success.
- **Why:** nginx reports that only in its error log, which is a fragile thing to parse. `nginx -t` catches config errors before the reload.
- **Where:** `stack/08-nginx.sh`

## D-14: A failure halfway through step 8 restores on the next run

- **Kind:** known limit
- **Decided:** 2026-11-22, #5 (PR #59)
- **What:** step 8 restores its old config only when `nginx -t` or the reload fails. If another command fails in between (a full disk, for one), the step stops with its files half written and the copy still in `/etc/nginx/eeploi.prev`. The next run takes that copy as the old config, and the check fails while it is there.
- **Why:** a running nginx keeps its loaded config until a reload, so sites keep working meanwhile. A trap for every failure would also catch the steps that run after this one in the same script.
- **Where:** `stack/08-nginx.sh`

## D-15: The real visitor IPs are a step of their own

- **Kind:** decision
- **Decided:** 2026-11-22, #5 (PR #59)
- **What:** `cloudflare.conf` (the `set_real_ip_from` lines, `{real_ip}`) is written by `stack/08-real-ip.sh`, a `window` step. The rest of the nginx config is step 8, an `always` step.
- **Why:** eeploi fills in `{real_ip}` at the first boot. On a live server the helper fills only `{user}`, `{port}`, `{php}`, `{version}` and `{name}`, so a step that holds `{real_ip}` can't be `always`. Rejected: step 8 with a rollback but staying `window`; Cloudflare's ranges in the values file, which needs a helper change. A later option is #61: the lines from `{ranges}`.
- **Where:** `stack/08-real-ip.sh`

## D-16: Probes, one per piece of software

- **Kind:** decision
- **Decided:** 2026-11-22, #63
- **What:** a probe (`NN-name.probe.sh`, listed in `ubuntu-*/probes`) prints the settings in effect for one piece of software, as `<key> <value>` lines. It detects its software first: not there, no lines and exit 0. It reads what the software itself reads after every drop-in (`sshd -T`, `nginx -T`, `php-fpm -tt`), not the files one by one, and prints only the keys in its own list. `--safe` names the settings whose values are safe to show. A probe takes no values from `recipes.conf` and writes nothing. Its stderr is not part of its output, and a probe that fails says so only by its exit status. npm's and Composer's versions are read from their files: a probe runs neither.
- **Why:** the same probe reads a server the steps set up and one they didn't, whoever wrote the files. The software's own reading is what it will run with. A fixed list of keys keeps secrets out; an error message could quote a config line, so it is not shown.
- **Accepted:** a setting a probe doesn't list is not shown, even where it matters; a new one is a new release.
- **Where:** `ubuntu-26.04/probes`

## D-17: Probes read the config on disk

- **Kind:** known limit
- **Decided:** 2026-11-22, #63
- **What:** as D-11 for the checks: `sshd -T`, `nginx -T`, `php-fpm -tt`, `postgres -C` and `mariadbd --print-defaults` read the config files, not what the running daemon loaded. A change not yet reloaded shows as if it were in effect.
- **Why:** none of them reports its running config without a login. The steps reload or restart after a change.
- **Where:** `stack/04-ssh.probe.sh`, `stack/08-nginx.probe.sh`, `ubuntu-26.04/01-php-fpm.probe.sh`, `ubuntu-26.04/01-postgresql.probe.sh`, `ubuntu-26.04/01-mysql.probe.sh`

## D-18: fail2ban shows counts, never addresses

- **Kind:** decision
- **Decided:** 2026-11-22, #63
- **What:** the fail2ban probe prints per jail the banned and failed counts, each as a number. The list of banned IPs is never printed, nor `ignoreip` among the safe settings.
- **Why:** a banned IP is a visitor's address: personal data, of no use in a report.
- **Where:** `stack/06-fail2ban.probe.sh`

## D-19: Redis shows where it listens, no settings

- **Kind:** known limit
- **Decided:** 2026-11-22, #63
- **What:** the Redis probe prints the addresses redis-server listens on (`ss`) and whether a `PING` without a password gets an answer. It shows none of Redis's settings.
- **Why:** Redis has no command that prints its config without connecting, and with a password set, connecting needs that password. Reading `redis.conf` would be reading the file, and the file holds the password.
- **Where:** `ubuntu-26.04/01-redis.probe.sh`

## D-20: Waiting updates as of the last package list update

- **Kind:** known limit
- **Decided:** 2026-11-22, #63
- **What:** the apt probe counts the updates waiting from the package lists on the server, by a simulated upgrade. It doesn't update the lists. The count is as old as `lists-updated` says.
- **Why:** a probe needs no network. apt updates the lists daily on its own (step 7).
- **Where:** `stack/07-apt.probe.sh`

## D-21: Release tags and releases can't be changed

- **Kind:** decision
- **Decided:** 2026-11-17
- **What:** a `v*` tag can't be moved or deleted (the ruleset "protect release tags" blocks update and deletion of `refs/tags/v*`), and releases are immutable. A fix is a new version, never a changed one. `bin/release.sh` stops when immutable releases are off.
- **Why:** a server checks a release against its signed manifest, by version. A version that can change would make that check, and every record of which release a server ran, worth nothing.
- **Accepted:** a tag on the wrong commit, or a release published by mistake, stays. The next version replaces it.
- **Where:** `bin/release.sh`
