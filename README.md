<p align="center">
<a href="https://github.com/eeploi/recipes/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://github.com/eeploi/recipes/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
<a href="https://github.com/eeploi/recipes/releases/latest"><img src="https://img.shields.io/github/v/release/eeploi/recipes" alt="Latest release"></a>
<a href="LICENSE.md"><img src="https://img.shields.io/github/license/eeploi/recipes" alt="License"></a>
</p>

# eeploi recipes

## About

What [eeploi](https://eeploi.com) runs on a server it sets up, one bash file per step. You can read every line that runs as root right here.

eeploi keeps a pinned copy of these files, at a fixed commit, and renders them into the script a new server runs once, as root, at its first boot (cloud-init user data). Nothing on the server downloads this repo.

## Layout

| Folder | Holds |
|---|---|
| `stack/` | The steps every Ubuntu release shares: apt retries, the deploy user, sudo, SSH, the firewall, fail2ban, updates, nginx, logs, start; and their probes |
| `ubuntu-26.04/` | What differs per Ubuntu release: the list of steps (`steps`), the list of probes (`probes`), the packages (`01-packages.sh`) and their probes, and the source for another PHP version than Ubuntu's (`php-source.sh`) |
| `first-boot/` | Only for a server eeploi creates: the report of a failed step, the root password lock, the helper download and the host-key report |
| `bin/` | Not part of a server's script: the layout check, the render of the steps that shellcheck reads, the run of each `always` step twice (CI), the test that each check is read-only (CI), the test of the report to eeploi (CI), the test of the PHP source's retry (CI), the tests of the probes (CI), the release command and its build, and the test of the release command against a fake GitHub (CI) |

## Decisions

[DECISIONS.md](DECISIONS.md) records what was chosen on purpose, and the risks and limits accepted with it, each as `D-n`. A line that a decision shapes says so in a comment (`# D-3: …`). Audits read it first: a finding against an entry is reported as "challenges D-n".

## Steps

`ubuntu-26.04/steps` lists the files in the order they run, one per line. eeploi joins them with an empty line between each. Without a first boot, for a script printed to run by hand, the `first-boot/` lines are left out.

Each step sets `STEP` to its number and name, so a failure reports the step it failed in.

| Step | File | Does |
|---|---|---|
| 0 | `first-boot/00-lock-root.sh` | Locks root's password and records that it did (`/etc/eeploi/root-locked`) |
| 0 | `stack/00-values.sh` | Writes the values to `/etc/eeploi/recipes.conf` (Values) |
| 0 | `stack/00-apt-retries.sh` | apt tries a dropped connection five more times |
| 0 | `first-boot/00-helper-download.sh` | Downloads eeploi-helper and checks its signature and SHA-256 |
| 1 | `ubuntu-26.04/01-packages.sh` | nginx, PHP, Node, Redis, Supervisor, the database, Composer and a pinned npm, without Ubuntu's `globalignorefile` and its update notice |
| 2 | `stack/02-deploy-user.sh` | The deploy user, with eeploi's key only; cron and at for root and that user only; PHP-FPM's stock `[www]` pool closed (on demand, two workers, a socket only root may open), no `X-Powered-By` header, no session upload progress |
| 3 | `stack/03-sudo.sh` | eeploi-helper and its one sudo rule |
| 4 | `stack/04-ssh.sh` | SSH on its own port, keys only, no root login, three tries, no forwarding but local (`ssh -L`, TCP and Unix sockets), Diffie-Hellman groups of 3072 bits and up (in `/etc/ssh/eeploi-moduli`), no NIST curves or SHA-1 offered, host keys ed25519 and RSA |
| 5 | `stack/05-firewall.sh` | UFW: SSH, and HTTPS from Cloudflare only |
| 6 | `stack/06-fail2ban.sh` | fail2ban for SSH: bans of 1 hour that double with each new ban within a day (capped at a week), and the recidive jail (five bans in a day: every port, a week); taken at once by a running fail2ban; the old jail stays when fail2ban refuses the new one |
| 6 | `stack/06-fail2ban-trusted.sh` | eeploi's own addresses, one each, never banned by any jail (`/etc/fail2ban/jail.d/eeploi-trusted.conf`); the old file stays when fail2ban refuses the new one |
| 7 | `stack/07-updates.sh` | Security updates only, Ubuntu's and Ubuntu Pro's (Ubuntu's own list of origins cleared), and every update of a PHP from packages.sury.org, services restarted after one, a package update keeps the config files eeploi changed, the SCTP, RDS and TIPC kernel modules blocked, no ICMP redirects taken or sent, martians logged (`/etc/sysctl.d/60-eeploi-network.conf`), no restart by Ctrl+Alt+Del (`ctrl-alt-del.target` masked, `CtrlAltDelBurstAction=none` in `/etc/systemd/system.conf.d/60-eeploi-ctrl-alt-del.conf`) |
| 8 | `stack/08-real-ip.sh` | Real visitor IPs: nginx takes `CF-Connecting-IP` from Cloudflare's ranges (`/etc/nginx/conf.d/cloudflare.conf`) |
| 8 | `stack/08-nginx.sh` | Room for large FastCGI headers, no default site, a catch-all that refuses the TLS handshake for unknown hosts; taken at once by a running nginx; the old config comes back when nginx refuses the new one or doesn't reload |
| 9 | `stack/09-logs.sh` | Log rotation for eeploi's worker and scheduler logs |
| 10 | `stack/10-start.sh` | Starts the services, checks SSH listens on IPv4 |
| 11 | `first-boot/11-report.sh` | Sends the host keys to eeploi, every 30 seconds until eeploi takes or refuses them |

`php-source.sh` adds packages.sury.org/php (Ondřej Surý) as a fixed source for another PHP than Ubuntu's own (8.3 and 8.4 on 26.04), with its signing key (15058500A0235D97F5D10063B188E2B695BD4743) pinned, and removes the Launchpad PPA, which has no builds for 26.04. When `apt-get update` of that source fails with a sync error, as while packages.sury.org syncs its mirrors, it tries again every 60 seconds for ten minutes, then stops step 1 with "The PHP source is updating; try again later." Any other error stops step 1 at once, with apt's first error.

`stack/start.sh`, `first-boot/start.sh` and `stack/values.sh` are no steps: they set the shell options, the reports to eeploi and the values. Nor is `stack/fingerprint.sh` (Fingerprint), which is not part of a server's script, nor are the probes ([PROBES.md](PROBES.md)).

## Markers

`markers` gives each step one marker, which says when it may run:

| Marker | Runs |
|---|---|
| `first-boot` | Only when a server is installed. Every step in `first-boot/` has it |
| `always` | On a live server too, in a rollout to every server. The helper fills only `{user}`, `{port}`, `{php}`, `{version}` and `{name}` in it |
| `window` | On a live server only with a manual "update now" |

A third column may hold flags, comma separated, set by the pull request that changes the step: `security` (the change is a security fix), `needs-restart` (a service must restart for it), `needs-reboot` (it takes effect after a reboot). No flags, no column.

The markers are not part of a server's script, so a new server gets the same script with or without them.

## Checks

Each step `NN-name.sh` has a `NN-name.check.sh` next to it: a read-only check that the step left the server as it should. A check reads the same values (`DEPLOY_USER`, `SSH_PORT`, `PHP`) and writes nothing. In `bin/render.sh --checks` each check runs in its own subshell under `set -e`, so any line that fails fails it, and prints `ok` or `failed` with its file. Checks are not part of the first boot yet.

The lock-root check needs root's password locked. Once step 0 has locked it (`/etc/eeploi/root-locked`, root's), a password the owner set later (Reset root password, Set a new root password) passes too, with the note "root has a password (set after the first boot); root can't log in over SSH". No password never passes.

## Probes

A probe, one per piece of software, prints the settings in effect, for a report. [PROBES.md](PROBES.md) has the format, the probes and their lines, and their limits.

## CI

Two jobs run on every pull request and every push to `main`.
Each test case is a comment in `.github/workflows/ci.yml`, next to the step that runs it.

- **`check`**: the files, the release build and each step on its own.
  Every `.sh` passes `bash -n`, and shellcheck passes on the script `bin/render.sh` makes from the steps (they are fragments), on the checks and on `bin/`.
  The layout holds: `bin/check-layout.sh` says what it checks.
  Every `minisign -V` takes only a prehashed signature.
  The first boot's report to eeploi works against a fake eeploi.
  A release builds from a tag, matches its manifest, and refuses what the helper would refuse.
  `--verify` takes only a release that is unchanged and signed, prehashed, with the right key.
  The key in `minisign.pub` is `RECIPES_PUBKEY` in the helper release CI pins (`HELPER_TAG`), and the provider name rule in `bin/` is the one `recipe-run` checks there.
  In a fresh Ubuntu 26.04 container, each `always` step runs twice as the helper runs it, leaves `/etc` the same on the second run, fails no unit, and passes its check.
  Each check is read-only, and where `ci.yml` tests it, fails without what its step writes.
  The fingerprint prints only known facts.
  In a fresh Ubuntu 26.04 container without the software, each probe prints nothing but the apt and kernel ones, and no error.
- **`server`**: a whole server, built as eeploi builds one, passes the helper's own `recipe-run`, with Ubuntu's own PHP and with a PHP from packages.sury.org.
  The helper is the release CI pins, with only its recipes key and its release address changed for a test key and a local server.
  `recipe-run` on a release built in CI ends `result ok` twice, the second time with every step the same, and fails when a check fails.
  Root's password: a password set passes with a note when step 0 locked root first (`/etc/eeploi/root-locked`) and fails without that; no password fails both; locked passes both, without a note.
  npm, as the deploy user runs it, prints no warning and no update notice.
  The settings SSH runs with, after every drop-in, are step 4's.
  nginx refuses the TLS handshake for an unknown host.
  The deploy user logs in with OpenSSH's client and a key, as eeploi does, and gets the ed25519 host key.
  ssh-audit reports on SSH's crypto, a report only.
  Each probe, run twice as the helper runs it, leaves `/etc` the same, prints only `<key> <value>` lines and the lines expected, and never a secret planted in the config files, a banned IP or eeploi's own addresses.
  The PHP source's pinned key is the one apt checks it with.
  Last, Lynis audits the server with Ubuntu's PHP: its hardening index, warnings and suggestions go to the job summary and the report is kept, a report only, never a failure.

A CI change updates the comments in `ci.yml`. This section changes only when what a job guarantees changes.

## Values

eeploi fills in the values before the script goes to the server:

- `{name}` inside a line is one value, such as `{user}`, `{port}` or `{ranges}`.
- `{name}` alone on its line stands for whole lines that eeploi renders itself, such as `{helper_install}`. When it is empty, the line goes too.

Step 0 writes the values a later run of the steps needs to `/etc/eeploi/recipes.conf`, root's, 0644. One `KEY=value` per line, each key once, `#` comments, nothing else. It is read, never sourced:

```
DEPLOY_USER=deploy
SSH_PORT=10022
PHP=8.4
```

Its check: `/etc/eeploi` is root's and 0755; the user (not root) and the port (22 or 10000 to 32767) are the ones the server runs with; `PHP` only has to be a version, since the default PHP may change later.

## Releases

`bin/release.sh VERSION MIN_HELPER PROVIDER...`, such as `bin/release.sh 0.4.3 1.1.0 example`, is the one release command. Run it in your own terminal: minisign asks for the key password. It releases `main`'s head: there is no tag before, publishing makes it (D-21). It first shows the repo and whether `main` is the same as GitHub's, the commit, the tag if it already exists, the eeploi-helper release `MIN_HELPER` and whether it exists, the targets, the key file and its key id, and the release and its title, `eeploi-recipes VERSION`. Then it runs eight steps, `Step N of 8`, and stops on the first failure:

1. **Checks:** on `main`, nothing uncommitted, `main` the same as GitHub's, every local `v*` tag the same as GitHub's (the build reads them for the manifest's versions), no tag `vVERSION` here or on GitHub, `VERSION` higher than every `v*` tag (compared as numbers: releases only go up), no release or draft yet for this version, CI green on `main`'s head, the helper release there, the key's public key (`.pub` next to the secret key) the same as `minisign.pub`, immutable releases on, and `dist/VERSION/` free. A draft left by a run that stopped stops here, with how to check and delete it.
2. **Build:** `bin/build-release.sh` (below), from the checked commit.
3. **Sign:** each manifest with the recipes key (`~/.minisign/eeploi-recipes.key`, or `RECIPES_KEY`), prehashed (`-H`), never `-l`.
4. **Verify:** `bin/build-release.sh --verify` against `minisign.pub`.
5. **Draft:** asks first, then creates the GitHub release as a draft on the checked commit, with the package, the manifests and their `.minisig` files. A draft has no tag yet and can be deleted.
6. **Verify the draft:** the draft is a draft on the checked commit with the right title and only those files. It downloads them again, compares them byte for byte with the files built and signed, and runs the step 4 checks on them (`RECIPES_DIR`).
7. **Publish:** checks that the tag is still not on GitHub, then publishes the draft. That makes the tag on the checked commit (lightweight, made by GitHub) and the release immutable: this can't be undone. A publish error says whether the release is still a draft, published, or unknown.
8. **Check after:** the release is published, immutable, with the right title and only those files. It downloads them again and checks them as in step 6, then fetches the tag and checks that it is on the checked commit.

A run that stops before step 7 leaves at most a draft, with no tag, and says so: check it, delete it (`gh release delete vVERSION -R eeploi/recipes`) and run again. Until it is gone, the checks stop on it. A run that stops after publishing has released the version.

`bin/release.sh --check VERSION MIN_HELPER PROVIDER...` runs step 1 only: no key, no build, nothing published.

`bin/build-release.sh VERSION MIN_HELPER PROVIDER...` builds a release from its tag `vVERSION`, not from the working copy, in `dist/VERSION/`. `RECIPES_COMMIT` builds it from that commit instead, before the tag exists, as `bin/release.sh` does; a tag `vVERSION` on another commit is refused, and the files are the same, byte for byte, as from a tag on that commit. It makes one package with every file a server runs (`recipes-VERSION.tar.gz`) and a manifest per provider and Ubuntu release (`recipes-VERSION-PROVIDER-ubuntu-26.04.manifest`). It refuses a file that is not a plain file, such as a link, a path the helper refuses (each part must match `[A-Za-z0-9_][A-Za-z0-9._-]*`, so none starts with `-` or `.`), and a NUL in a list of steps or in `markers`, which bash would drop unseen. It signs nothing. The signature covers the whole manifest, and the manifest has the SHA-256 of every file.

`bin/build-release.sh --verify VERSION MIN_HELPER PROVIDER...`, with the same values, builds the release again from its tag (or `RECIPES_COMMIT`) and changes nothing. `dist/VERSION/` must hold exactly the files built, with the same bytes, and a `.minisig` per manifest that verifies the manifest built against `minisign.pub`, the recipes public key (its key id is in its first line). Only prehashed signatures (algorithm `ED`, minisign's default) count: a legacy one (`minisign -l`, `Ed`) is refused, as the helper refuses it. A manifest signed with another key, a stale signature or a changed file fails here, before upload. `RECIPES_DIR` sets another folder to verify than `dist/VERSION/`, with `--verify` only. The key in `minisign.pub` must be the same as `RECIPES_PUBKEY` in eeploi-helper.

A manifest is plain text, one fact per line:

```
format 1
release 0.4.0
target example ubuntu-26.04
min-helper 0.5.0
step <sha256> <marker> <introduced> <changed> <flags|-> <path>
file <sha256> <path>
```

`min-helper` is the eeploi-helper release needed to run it. The `step` lines are in run order, with the marker and flags from `markers`, the release the step came in and the first release since which it is the same. The `file` lines are the other files a run reads: `start.sh`, `values.sh`, the checks, the probes (in the order of `probes`), `php-source.sh` and `fingerprint.sh`.

## Fingerprint

`stack/fingerprint.sh`, run as root, reads what the provider's image brought and prints it, one fact per line; a key may repeat. It writes nothing.

```
fingerprint 1
kernel 6.17.0-8-generic
swap 0
cloud-init-datasource nocloud
default-user none
apt-mirror http://archive.ubuntu.com/ubuntu
agent qemu-guest-agent
```

`swap` is in kB. `default-user` is each user with a login and a regular UID, apart from the deploy user, or `none`. `agent` is a known provider agent, installed as a package or a snap.

## Pinned copy

eeploi pins the commit and the SHA-256 of the files in `first-boot/`, `stack/` and `ubuntu-*/`, taken as:

```bash
find first-boot stack ubuntu-* -type f | LC_ALL=C sort | xargs sha256sum | sha256sum
```

Each server eeploi builds records that commit and SHA-256.

## Contributing

Thank you for considering a contribution. The [contribution guide](.github/CONTRIBUTING.md) says how.

## Security Vulnerabilities

Please report a security problem privately, as the [security policy](.github/SECURITY.md) describes, never in a public issue.

## License

eeploi recipes is open-sourced software licensed under the [MIT license](LICENSE.md).
