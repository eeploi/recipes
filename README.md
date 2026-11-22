# eeploi recipes

What [eeploi](https://eeploi.com) runs on a server it sets up, one bash file per step. You can read every line that runs as root right here.

eeploi keeps a pinned copy of these files, at a fixed commit, and renders them into the script a new server runs once, as root, at its first boot (cloud-init user data). Nothing on the server downloads this repo.

## Layout

| Folder | Holds |
|---|---|
| `stack/` | The steps every Ubuntu release shares: apt retries, the deploy user, sudo, SSH, the firewall, fail2ban, updates, nginx, logs, start |
| `ubuntu-26.04/` | What differs per Ubuntu release: the list of steps (`steps`), the packages (`01-packages.sh`) and the source for another PHP version than Ubuntu's (`php-source.sh`) |
| `first-boot/` | Only for a server eeploi creates: the report of a failed step, the root password lock, the helper download and the host-key report |
| `bin/` | Not part of a server's script: the layout check, the render of the steps that shellcheck reads, the run of each `always` step twice (CI), the test that each check is read-only (CI), the test of the report to eeploi (CI), the test of the PHP source's retry (CI), and the release command and its build |

## Steps

`ubuntu-26.04/steps` lists the files in the order they run, one per line. eeploi joins them with an empty line between each. Without a first boot, for a script printed to run by hand, the `first-boot/` lines are left out.

Each step sets `STEP` to its number and name, so a failure reports the step it failed in.

| Step | File | Does |
|---|---|---|
| 0 | `first-boot/00-lock-root.sh` | Locks root's password |
| 0 | `stack/00-values.sh` | Writes the values to `/etc/eeploi/recipes.conf` (Values) |
| 0 | `stack/00-apt-retries.sh` | apt tries a dropped connection five more times |
| 0 | `first-boot/00-helper-download.sh` | Downloads eeploi-helper and checks its signature and SHA-256 |
| 1 | `ubuntu-26.04/01-packages.sh` | nginx, PHP, Node, Redis, Supervisor, the database, Composer and a pinned npm, without Ubuntu's `globalignorefile` and its update notice |
| 2 | `stack/02-deploy-user.sh` | The deploy user, with eeploi's key only; cron and at for root and that user only |
| 3 | `stack/03-sudo.sh` | eeploi-helper and its one sudo rule |
| 4 | `stack/04-ssh.sh` | SSH on its own port, keys only, no root login, three tries, no forwarding but local (`ssh -L`, TCP and Unix sockets), Diffie-Hellman groups of 3072 bits and up (in `/etc/ssh/eeploi-moduli`), no NIST curves or SHA-1 offered, host keys ed25519 and RSA |
| 5 | `stack/05-firewall.sh` | UFW: SSH, and HTTPS from Cloudflare only |
| 6 | `stack/06-fail2ban.sh` | fail2ban for SSH: bans of 1 hour that double for a repeat offender, up to a week, and the recidive jail (five bans in a day: every port, a week); taken at once by a running fail2ban; the old jail stays when fail2ban refuses the new one |
| 7 | `stack/07-updates.sh` | Security updates only, services restarted after one, SCTP kernel module blocked |
| 8 | `stack/08-nginx.sh` | Real visitor IPs, a catch-all that refuses the TLS handshake for unknown hosts |
| 9 | `stack/09-logs.sh` | Log rotation for eeploi's worker and scheduler logs |
| 10 | `stack/10-start.sh` | Starts the services, checks SSH listens on IPv4 |
| 11 | `first-boot/11-report.sh` | Sends the host keys to eeploi, every 30 seconds until eeploi takes or refuses them |

`php-source.sh` adds packages.sury.org/php (Ondřej Surý) as a fixed source for another PHP than Ubuntu's own (8.3 and 8.4 on 26.04), with its signing key (15058500A0235D97F5D10063B188E2B695BD4743) pinned, and removes the Launchpad PPA, which has no builds for 26.04. When `apt-get update` of that source fails with a sync error, as while packages.sury.org syncs its mirrors, it tries again every 60 seconds for ten minutes, then stops step 1 with "The PHP source is updating; try again later." Any other error stops step 1 at once, with apt's first error.

`stack/start.sh`, `first-boot/start.sh` and `stack/values.sh` are no steps: they set the shell options, the reports to eeploi and the values. Nor is `stack/fingerprint.sh` (Fingerprint), which is not part of a server's script.

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
- **`server`**: a whole server, built as eeploi builds one, passes the helper's own `recipe-run`, with Ubuntu's own PHP and with a PHP from packages.sury.org.
  The helper is the release CI pins, with only its recipes key and its release address changed for a test key and a local server.
  `recipe-run` on a release built in CI ends `result ok` twice, the second time with every step the same, and fails when a check fails.
  npm, as the deploy user runs it, prints no warning and no update notice.
  The settings SSH runs with, after every drop-in, are step 4's.
  nginx refuses the TLS handshake for an unknown host.
  The deploy user logs in with OpenSSH's client and a key, as eeploi does, and gets the ed25519 host key.
  ssh-audit reports on SSH's crypto, a report only.
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

`bin/release.sh VERSION MIN_HELPER PROVIDER...`, such as `bin/release.sh 0.4.3 1.1.0 example`, is the one release command. Run it in your own terminal: minisign asks for the key password. It first shows the repo and whether `main` is the same as GitHub's, the tag and its commit, the eeploi-helper release `MIN_HELPER` and whether it exists, the targets, the key file and its key id, and the release and its title, `eeploi-recipes VERSION`. Then it runs six steps, `Step N of 6`, and stops on the first failure:

1. **Checks:** on `main`, nothing uncommitted, `main` the same as GitHub's, the tag on GitHub at the same commit and on `main`, CI green on it, the helper release there, the key's public key (`.pub` next to the secret key) the same as `minisign.pub`, no release or draft yet for this version, immutable releases on, every local `v*` tag the same as GitHub's (the build reads them for the manifest's versions), and `dist/VERSION/` free.
2. **Build:** `bin/build-release.sh` (below).
3. **Sign:** each manifest with the recipes key (`~/.minisign/eeploi-recipes.key`, or `RECIPES_KEY`), prehashed (`-H`), never `-l`.
4. **Verify:** `bin/build-release.sh --verify` against `minisign.pub`.
5. **Publish:** asks first, then creates the GitHub release with the package, the manifests and their `.minisig` files. Releases are immutable: this can't be undone.
6. **Check after:** downloads the release again and runs the step 4 checks on it (`RECIPES_DIR`): the files a fresh build from the tag makes, byte for byte, and signatures that verify against `minisign.pub`. The title must be right and the release immutable.

`bin/release.sh --check VERSION MIN_HELPER PROVIDER...` runs step 1 only: no key, no build, nothing published.

`bin/build-release.sh VERSION MIN_HELPER PROVIDER...` builds a release from its tag `vVERSION`, not from the working copy, in `dist/VERSION/`: one package with every file a server runs (`recipes-VERSION.tar.gz`) and a manifest per provider and Ubuntu release (`recipes-VERSION-PROVIDER-ubuntu-26.04.manifest`). It refuses a file that is not a plain file, such as a link, a path the helper refuses (each part must match `[A-Za-z0-9_][A-Za-z0-9._-]*`, so none starts with `-` or `.`), and a NUL in a list of steps or in `markers`, which bash would drop unseen. It signs nothing. The signature covers the whole manifest, and the manifest has the SHA-256 of every file.

`bin/build-release.sh --verify VERSION MIN_HELPER PROVIDER...`, with the same values, builds the release again from its tag and changes nothing. `dist/VERSION/` must hold exactly the files built, with the same bytes, and a `.minisig` per manifest that verifies the manifest built against `minisign.pub`, the recipes public key (its key id is in its first line). Only prehashed signatures (algorithm `ED`, minisign's default) count: a legacy one (`minisign -l`, `Ed`) is refused, as the helper refuses it. A manifest signed with another key, a stale signature or a changed file fails here, before upload. `RECIPES_DIR` sets another folder to verify than `dist/VERSION/`, with `--verify` only. The key in `minisign.pub` must be the same as `RECIPES_PUBKEY` in eeploi-helper.

A manifest is plain text, one fact per line:

```
format 1
release 0.4.0
target example ubuntu-26.04
min-helper 0.5.0
step <sha256> <marker> <introduced> <changed> <flags|-> <path>
file <sha256> <path>
```

`min-helper` is the eeploi-helper release needed to run it. The `step` lines are in run order, with the marker and flags from `markers`, the release the step came in and the first release since which it is the same. The `file` lines are the other files a run reads: `start.sh`, `values.sh`, the checks, `php-source.sh` and `fingerprint.sh`.

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

## License

MIT. See [LICENSE](LICENSE).
