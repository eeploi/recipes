# Changelog

All notable changes to eeploi recipes, in the style of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [semver](https://semver.org); while eeploi is in development they stay on 0.x: a patch release is a fix that leaves servers the same, a minor release a new or changed step. A release's date is the date of its GitHub release.

`bin/release.sh` releases the top version below, and only while `## Unreleased` is empty.

## Unreleased

### Added

- `first-boot/00-apt-timers.sh` and its check: the first boot stops apt's daily timers before step 1 and waits up to five minutes for a daily job already running, since `apt-get update` fails at once while apt's lists lock is held; step 7 stops them again after its upgrade, as an apt update starts them; they stay enabled and start again with the reboot after the first boot (#77).
- `first-boot/07-upgrade.sh` and its check: the first boot installs every update Ubuntu offers this server now, after step 7 and before step 10, so a new server has no known update missing; a failed update fails the first boot (D-28, #71).
- The nginx probe prints `nginx-conf-dpkg-dist yes|no`: whether a newer stock `nginx.conf` waits next to the one in use (#72).

### Changed

- Step 0 (`stack/00-apt-retries.sh`) also has every apt install and upgrade wait up to five minutes for dpkg's lock (`DPkg::Lock::Timeout "300"` in `/etc/apt/apt.conf.d/80-eeploi-retries`), which apt's timers can hold at first boot; its check fails without it. `first-boot/07-upgrade.sh` takes it from there (#77).
- Step 8 turns nginx's `server_tokens` off in `/etc/nginx/nginx.conf` (Ubuntu's file sets `build`), so no nginx version or build name shows in the `Server` header or on error pages; its check fails when nginx.conf doesn't turn it off or any file nginx reads turns it on again. D-27: an nginx update keeps the changed `nginx.conf` (#72).

## 0.6.0

### Breaking

What a renderer of the first boot must change:

- New value `{trusted_ips}`: eeploi's own addresses, space separated, each a single IPv4 or IPv6 address, in the new `window` step `stack/06-fail2ban-trusted.sh`, after step 6. An empty list is valid (#66).
- `{real_ip}` moved from `stack/08-nginx.sh` to the new `window` step `stack/08-real-ip.sh`, before step 8 (#59).
- Step 8 (`stack/08-nginx.sh`) is `always` now, was `window`: it holds no value the helper doesn't fill (#59).

### Added

- `stack/06-fail2ban-trusted.sh` and its check: eeploi's own addresses are never banned by any jail, `recidive` included (`/etc/fail2ban/jail.d/eeploi-trusted.conf`) (#66).
- `stack/08-real-ip.sh` and its check: nginx takes `CF-Connecting-IP` from Cloudflare's ranges, the same file as before, and the step runs `nginx -t` itself (#59).
- Probes, one per piece of software, that print the settings in effect, listed in `ubuntu-26.04/probes` and shipped in the release as `file` lines; see PROBES.md (#64).
- DECISIONS.md: the decisions, accepted risks and known limits, with a `# D-n` comment at the lines each one shapes (#62, #65).
- CHANGELOG.md (this file), and a `providers` file with the providers a release is built for.
- Repo docs: LICENSE.md, `.github/SECURITY.md`, a contribution guide, issue forms and a pull request template (#52, #53, #54).

### Changed

- Step 7: Ctrl+Alt+Del restarts nothing: `ctrl-alt-del.target` masked and `CtrlAltDelBurstAction=none` (#58).
- Step 8 keeps the files it changes aside until nginx takes the new config and reloads, and puts them back when it doesn't (#59).
- Step 0 records that it locked root's password (`/etc/eeploi/root-locked`). The lock-root check then passes on a root password set later, with a note; a password step 0 never locked still fails (#57).
- `bin/release.sh` takes no values: the version from this file, the helper from CI's `HELPER_TAG`, the providers from `providers`. It refuses to release without a version heading here, or with lines under `## Unreleased`.
- `bin/release.sh` releases from a draft it downloads and verifies first; publishing makes the tag, so a run that stops before that leaves the version free (#69).
- CI tests with eeploi-helper 1.2.0, its `server-report` included.

## 0.5.0 and older

See the [GitHub releases](https://github.com/eeploi/recipes/releases).
