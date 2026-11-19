# eeploi recipes

What [eeploi](https://eeploi.com) runs on a server it sets up, one bash file per step. You can read every line that runs as root right here.

eeploi keeps a pinned copy of these files, at a fixed commit, and renders them into the script a new server runs once, as root, at its first boot (cloud-init user data). Nothing on the server downloads this repo.

## Layout

| Folder | Holds |
|---|---|
| `stack/` | The steps every Ubuntu release shares: apt retries, the deploy user, sudo, SSH, the firewall, fail2ban, updates, nginx, logs, start |
| `ubuntu-26.04/` | What differs per Ubuntu release: the list of steps (`steps`), the packages (`01-packages.sh`) and the source for another PHP version than Ubuntu's (`php-source.sh`) |
| `first-boot/` | Only for a server eeploi creates: the report of a failed step, the root password lock, the helper download and the host-key report |
| `bin/` | Not part of a server's script: the layout check, the render of the steps that shellcheck reads, the run of each `always` step twice (CI), and the release build |

## Steps

`ubuntu-26.04/steps` lists the files in the order they run, one per line. eeploi joins them with an empty line between each. Without a first boot, for a script printed to run by hand, the `first-boot/` lines are left out.

Each step sets `STEP` to its number and name, so a failure reports the step it failed in.

| Step | File | Does |
|---|---|---|
| 0 | `first-boot/00-lock-root.sh` | Locks root's password |
| 0 | `stack/00-values.sh` | Writes the values to `/etc/eeploi/recipes.conf` (Values) |
| 0 | `stack/00-apt-retries.sh` | apt tries a dropped connection five more times |
| 0 | `first-boot/00-helper-download.sh` | Downloads eeploi-helper and checks its signature and SHA-256 |
| 1 | `ubuntu-26.04/01-packages.sh` | nginx, PHP, Node, Redis, Supervisor, the database, Composer and a pinned npm |
| 2 | `stack/02-deploy-user.sh` | The deploy user, with eeploi's key only; cron and at for root and that user only |
| 3 | `stack/03-sudo.sh` | eeploi-helper and its one sudo rule |
| 4 | `stack/04-ssh.sh` | SSH on its own port, keys only, no root login |
| 5 | `stack/05-firewall.sh` | UFW: SSH, and HTTPS from Cloudflare only |
| 6 | `stack/06-fail2ban.sh` | fail2ban for SSH, taken at once by a running fail2ban |
| 7 | `stack/07-updates.sh` | Security updates only, services restarted after one, SCTP kernel module blocked |
| 8 | `stack/08-nginx.sh` | Real visitor IPs, a catch-all for unknown hosts |
| 9 | `stack/09-logs.sh` | Log rotation for eeploi's worker and scheduler logs |
| 10 | `stack/10-start.sh` | Starts the services, checks SSH listens on IPv4 |
| 11 | `first-boot/11-report.sh` | Sends the host keys to eeploi |

`php-source.sh` adds the ondrej PPA as a fixed source, with its key (14AA40EC0831756756D7F66C4F4EA0AAE5267A6C) pinned, so a first boot needs no Launchpad API.

`stack/start.sh`, `first-boot/start.sh` and `stack/values.sh` are no steps: they set the shell options, the failure report and the values. Nor is `stack/fingerprint.sh` (Fingerprint), which is not part of a server's script.

## Markers

`markers` gives each step one marker, which says when it may run:

| Marker | Runs |
|---|---|
| `first-boot` | Only when a server is installed. Every step in `first-boot/` has it |
| `always` | On a live server too, in a rollout to every server |
| `window` | On a live server only with a manual "update now" |

A third column may hold flags, comma separated, set by the pull request that changes the step: `security` (the change is a security fix), `needs-restart` (a service must restart for it), `needs-reboot` (it takes effect after a reboot). No flags, no column.

The markers are not part of a server's script, so a new server gets the same script with or without them.

## Checks

Each step `NN-name.sh` has a `NN-name.check.sh` next to it: a read-only check that the step left the server as it should. A check reads the same values (`DEPLOY_USER`, `SSH_PORT`, `PHP`) and writes nothing. In `bin/render.sh --checks` each check runs in its own subshell under `set -e`, so any line that fails fails it, and prints `ok` or `failed` with its file. Checks are not part of the first boot yet.

## CI

One job on every pull request and push to `main`: `bash -n` on every `.sh`, `bin/check-layout.sh` (every file in `steps` exists, and each step sets `STEP=`, has its check, has one marker in `markers` and is in the table above), and shellcheck on the script `bin/render.sh` makes from `steps`, with and without `first-boot/`, and on the checks with the values in front. The step files are fragments, so shellcheck can't read them one by one. `first-boot/00-helper-download.sh` and `first-boot/11-report.sh` have no check, by name in `bin/check-layout.sh`. Then `bin/run-twice.sh` runs each `always` step twice in a fresh `ubuntu:26.04` container, then its check, and fails a step whose second run changes `/etc`. Then the check of step 7 must fail without its apt lines, step 0 writes the values file twice and its check must fail on a changed file, and the fingerprint must print only known facts, in the container and on the runner. Last, `bin/release.sh` builds a release from a local tag, and every file in its package must match its manifest.

## Values

eeploi fills in the values before the script goes to the server:

- `{name}` inside a line is one value, such as `{user}`, `{port}` or `{ranges}`.
- `{name}` alone on its line stands for whole lines that eeploi renders itself, such as `{helper_install}`. When it is empty, the line goes too.

Step 0 writes the values a later run of the steps needs to `/etc/eeploi/recipes.conf`, root's, 0644. One `KEY=value` per line, each key once, `#` comments, nothing else. It is read, never sourced:

```
DEPLOY_USER=deploy
SSH_PORT=2222
PHP=8.4
```

Its check: `/etc/eeploi` is root's and 0755; the user (not root) and the port (22 or 10000 to 32767) are the ones the server runs with; `PHP` only has to be a version, since the default PHP may change later.

## Releases

`bin/release.sh VERSION MIN_HELPER PROVIDER...` builds a release from its tag `vVERSION`, not from the working copy, in `dist/VERSION/`: one package with every file a server runs (`recipes-VERSION.tar.gz`) and a manifest per provider and Ubuntu release (`recipes-VERSION-PROVIDER-ubuntu-26.04.manifest`). It signs nothing: it prints the manifests to sign with the recipes minisign key. The signature covers the whole manifest, and the manifest has the SHA-256 of every file.

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
