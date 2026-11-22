# Decisions

Choices made on purpose, and the risks and limits accepted with them, so an audit can tell a choice from a mistake.

## For reviewers and audits

- Read this file first.
- A finding against an entry here is not a bug. Report it as "challenges D-n", with an argument the entry doesn't already answer.
- A rejected audit finding becomes a new entry, so the next audit doesn't raise it again.

## How entries work

- One entry per decision, numbered `D-1`, `D-2` and so on. A number is never reused or renumbered.
- **Kind** is `decision`, `accepted risk` or `known limit`.
- **Decided** gives the date and the issue or pull request in this repo.
- **Where** names the files the entry shapes. The line it shapes carries a comment `# D-n: …`. `bin/check-layout.sh` fails on a `D-n` comment without an entry here.
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
- **Decided:** 2026-11-21, #26 (PR #34), PR #38
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
