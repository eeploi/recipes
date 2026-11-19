# eeploi recipes

What [eeploi](https://eeploi.com) runs on a server it sets up, one bash file per step. You can read every line that runs as root right here.

eeploi keeps a pinned copy of these files, at a fixed commit, and renders them into the script a new server runs once, as root, at its first boot (cloud-init user data). Nothing on the server downloads this repo.

## Layout

| Folder | Holds |
|---|---|
| `stack/` | The steps every Ubuntu release shares: the deploy user, sudo, SSH, the firewall, fail2ban, updates, nginx, logs, start |
| `ubuntu-26.04/` | What differs per Ubuntu release: the list of steps (`steps`), the packages (`01-packages.sh`) and the source for another PHP version than Ubuntu's (`php-source.sh`) |
| `first-boot/` | Only for a server eeploi creates: the report of a failed step, the root password lock, the helper download and the host-key report |
| `bin/` | For CI, not part of a server's script: the layout check and the render of the steps that shellcheck reads |

## Steps

`ubuntu-26.04/steps` lists the files in the order they run, one per line. eeploi joins them with an empty line between each. Without a first boot, for a script printed to run by hand, the `first-boot/` lines are left out.

Each step sets `STEP` to its number and name, so a failure reports the step it failed in.

| Step | File | Does |
|---|---|---|
| 0 | `first-boot/00-lock-root.sh` | Locks root's password |
| 0 | `first-boot/00-helper-download.sh` | Downloads eeploi-helper and checks its signature and SHA-256 |
| 1 | `ubuntu-26.04/01-packages.sh` | nginx, PHP, Node, Redis, Supervisor, the database, Composer and a pinned npm |
| 2 | `stack/02-deploy-user.sh` | The deploy user, with eeploi's key only; cron and at for root and that user only |
| 3 | `stack/03-sudo.sh` | eeploi-helper and its one sudo rule |
| 4 | `stack/04-ssh.sh` | SSH on its own port, keys only, no root login |
| 5 | `stack/05-firewall.sh` | UFW: SSH, and HTTPS from Cloudflare only |
| 6 | `stack/06-fail2ban.sh` | fail2ban for SSH |
| 7 | `stack/07-updates.sh` | Security updates only, services restarted after one, SCTP kernel module blocked |
| 8 | `stack/08-nginx.sh` | Real visitor IPs, a catch-all for unknown hosts |
| 9 | `stack/09-logs.sh` | Log rotation for eeploi's worker and scheduler logs |
| 10 | `stack/10-start.sh` | Starts the services, checks SSH listens on IPv4 |
| 11 | `first-boot/11-report.sh` | Sends the host keys to eeploi |

`php-source.sh` adds the ondrej PPA as a fixed source, with its key (14AA40EC0831756756D7F66C4F4EA0AAE5267A6C) pinned, so a first boot needs no Launchpad API.

`stack/start.sh`, `first-boot/start.sh` and `stack/values.sh` are no steps: they set the shell options, the failure report and the values.

## Checks

Each step `NN-name.sh` has a `NN-name.check.sh` next to it: a read-only check that the step left the server as it should. A check reads the same values (`DEPLOY_USER`, `SSH_PORT`, `PHP`). Checks are not part of the first boot yet.

## CI

One job on every pull request and push to `main`: `bash -n` on every `.sh`, `bin/check-layout.sh` (every file in `steps` exists, and each step sets `STEP=`, has its check and is in the table above), and shellcheck on the script `bin/render.sh` makes from `steps`, with and without `first-boot/`, and on the checks with the values in front. The step files are fragments, so shellcheck can't read them one by one. `first-boot/00-helper-download.sh` and `first-boot/11-report.sh` have no check, by name in `bin/check-layout.sh`.

## Values

eeploi fills in the values before the script goes to the server:

- `{name}` inside a line is one value, such as `{user}`, `{port}` or `{ranges}`.
- `{name}` alone on its line stands for whole lines that eeploi renders itself, such as `{helper_install}`. When it is empty, the line goes too.

## Pinned copy

eeploi pins the commit and the SHA-256 of the files in `first-boot/`, `stack/` and `ubuntu-*/`, taken as:

```bash
find first-boot stack ubuntu-* -type f | LC_ALL=C sort | xargs sha256sum | sha256sum
```

Each server eeploi builds records that commit and SHA-256.

## License

MIT. See [LICENSE](LICENSE).
