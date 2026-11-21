#!/usr/bin/env bash
# The one release command: checks, builds from the tag, signs with the recipes key, verifies,
# publishes the GitHub release and checks what went up. It stops on the first failure.
# Run it yourself, in your own terminal: minisign asks for the key password, which is never
# stored, passed in or logged. Releases are immutable: step 5 asks before it publishes.
# --check runs step 1 only: no key, no build, nothing published.
# The secret key is ~/.minisign/eeploi-recipes.key, or RECIPES_KEY when set; its public key must
# be next to it (.pub) and the same as minisign.pub.
# Usage: bin/release.sh [--check] VERSION MIN_HELPER PROVIDER...   such as bin/release.sh 0.4.3 1.1.0 hetzner
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

REPO=eeploi/recipes
HELPER_REPO=eeploi/helper
STEPS=6
key=${RECIPES_KEY:-$HOME/.minisign/eeploi-recipes.key}
check_only=
[ "${1:-}" != --check ] || { check_only=1; shift; }
usage="Usage: bin/release.sh [--check] VERSION MIN_HELPER PROVIDER..."
[ "$#" -ge 3 ] || { echo "$usage" >&2; exit 2; }
version=$1
min_helper=$2
shift 2
providers=("$@")
semver='^[0-9]+\.[0-9]+\.[0-9]+$'
[[ "$version" =~ $semver ]] || { echo "$version is no version, such as 0.4.3" >&2; exit 2; }
[[ "$min_helper" =~ $semver ]] || { echo "$min_helper is no helper version, such as 1.1.0" >&2; exit 2; }
provider_name='^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$' # the helper's rule, as bin/build-release.sh
for provider in "${providers[@]}"; do
  [[ "$provider" =~ $provider_name ]] || { echo "$provider is no provider name: a-z, 0-9 and inner -, at most 32" >&2; exit 2; }
done
tag=v$version
title="eeploi-recipes $version"
out=dist/$version

step=0
published=
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() {
  echo "release: $*" >&2
  if [ -n "$published" ]; then
    echo "Stopped at step $step of $STEPS: $tag IS published. Look at it: gh release view $tag -R $REPO" >&2
  elif [ "$step" -gt 0 ]; then
    echo "Stopped at step $step of $STEPS: nothing was published." >&2
  fi
  exit 1
}
begin() { step=$((step + 1)); printf '\nStep %s of %s: %s\n' "$step" "$STEPS" "$1"; }
ok() { echo "  ✓ $*"; }
# key_id <public key file>: its key id as minisign prints it. In the base64 of line 2, bytes 3 to 10
# are the id, lowest byte first.
key_id() {
  local bytes id='' i
  read -ra bytes < <(sed -n 2p "$1" | base64 -d 2>/dev/null | od -An -tx1 -j2 -N8)
  for ((i = ${#bytes[@]} - 1; i >= 0; i--)); do id+=${bytes[i]}; done
  tr a-f A-F <<< "$id"
}
# remote_tag: the commit of $tag on GitHub, a plain tag or not, or nothing.
remote_tag() {
  local refs
  refs=$(git ls-remote origin "refs/tags/$tag" "refs/tags/$tag^{}")
  awk -v t="refs/tags/$tag^{}" '$2 == t { print $1; found = 1 } END { exit !found }' <<< "$refs" || awk 'NR == 1 { print $1 }' <<< "$refs"
}
# api_status <path>: 200 when GitHub has it, 404 when not; anything else stops.
api_status() {
  local err
  if gh api "$1" --silent 2>"$work/api"; then echo 200; return; fi
  err=$(cat "$work/api")
  case "$err" in *'HTTP 404'*) echo 404 ;; *) fail "GitHub did not answer for $1: $err" ;; esac
}

for cmd in git gh minisign base64 od; do
  command -v "$cmd" >/dev/null || fail "$cmd is not installed"
done

# What the header shows, read first: nothing changes but the fetch of main.
git fetch -q origin main
branch=$(git branch --show-current)
head=$(git rev-parse HEAD)
clean=; [ -n "$(git status --porcelain)" ] || clean=1
synced=; [ "$head" != "$(git rev-parse origin/main)" ] || synced=1
tagged=$(git rev-parse -q --verify "refs/tags/$tag^{commit}" || true)
remote_tagged=$(remote_tag)
helper_status=$(api_status "repos/$HELPER_REPO/releases/tags/v$min_helper")
release_status=$(api_status "repos/$REPO/releases/tags/$tag")
pub_id=$(key_id minisign.pub)
key_pub=${key%.key}.pub
key_pub_id=; [ ! -f "$key_pub" ] || key_pub_id=$(key_id "$key_pub")
oses=()
[ -z "$tagged" ] || while IFS= read -r os; do oses+=("$os"); done < <(git ls-tree --name-only "$tag" | grep '^ubuntu-' || true)

printf 'Recipes release %s\n' "$version"
printf '  repo     %s, on %s, %s%s\n' "$REPO" "${branch:-no branch}" \
  "$([ -n "$synced" ] && echo 'up to date' || echo 'NOT the same as GitHub')" "$([ -n "$clean" ] || echo ', uncommitted changes')"
if [ -z "$tagged" ]; then
  printf '  tag      %s does not exist\n' "$tag"
else
  printf '  tag      %s = %s%s\n' "$tag" "$(git rev-parse --short "$tagged")" "$([ "$remote_tagged" = "$tagged" ] || echo ' (NOT on GitHub as that)')"
fi
printf '  helper   needs %s (%s)\n' "$min_helper" "$([ "$helper_status" = 200 ] && echo 'released ✓' || echo 'NOT released')"
printf '  targets  %s on %s\n' "${providers[*]}" "${oses[*]:-?}"
printf '  key      %s (%s)\n' "${key/#$HOME/~}" "${key_pub_id:-no .pub next to it}"
printf '  release  %s, titled %s\n' "$([ "$release_status" = 404 ] && echo new || echo 'EXISTS')" "$title"

begin checks
[ "$branch" = main ] || fail "not on main"
[ -n "$clean" ] || fail "uncommitted changes"
[ -n "$synced" ] || fail "main is not the same as GitHub's main: pull or push first"
ok "on main at $(git rev-parse --short "$head"), clean, the same as GitHub"
[ -n "$tagged" ] || fail "$tag is no tag here: fetch the tags, or tag the release commit first"
[ "$remote_tagged" = "$tagged" ] || fail "$tag is not on GitHub as $(git rev-parse --short "$tagged") (GitHub: ${remote_tagged:-no such tag})"
git merge-base --is-ancestor "$tagged" origin/main || fail "$tag is not on main"
ok "$tag = $(git rev-parse --short "$tagged"), the same on GitHub, on main"
ci=$(gh run list -R "$REPO" --commit "$tagged" --workflow ci.yml --event push --json status,conclusion --jq '.[0] | "\(.status) \(.conclusion)"')
[ "$ci" = "completed success" ] || fail "CI on $tag is not green (${ci:-no run})"
ok "CI on $tag green"
[ "$helper_status" = 200 ] || fail "no eeploi-helper release v$min_helper"
ok "eeploi-helper v$min_helper released"
[ "${#oses[@]}" -gt 0 ] || fail "$tag has no ubuntu-* folder"
# The secret key's id can't be read without its password; its public key next to it must be
# minisign.pub, and step 3 checks the signatures against minisign.pub.
case "$key" in /*) ;; *) fail "RECIPES_KEY must be an absolute path: $key" ;; esac
[ -f "$key" ] || fail "no secret key at $key (set RECIPES_KEY to use another)"
[ -f "$key_pub" ] || fail "no public key at $key_pub next to the secret key"
[ "$(sed -n 2p "$key_pub")" = "$(sed -n 2p minisign.pub)" ] || fail "$key_pub ($key_pub_id) is not minisign.pub ($pub_id)"
ok "key $key_pub_id, the same as minisign.pub"
[ "$release_status" = 404 ] || fail "$REPO already has a release $tag: releases are immutable"
ok "no release $tag yet"
[ ! -e "$out" ] || fail "$out exists from an earlier run: remove it first (rm -r $out)"
ok "$out is free"
if [ -n "$check_only" ]; then
  printf '\nChecks passed. Nothing built or published (--check).\n'
  exit 0
fi
[ -t 0 ] || fail "run this in your own terminal: minisign asks for the key password"

begin build
bin/build-release.sh "$version" "$min_helper" "${providers[@]}" | sed 's/^/  /' || fail "the build failed"
[ -d "$out" ] || fail "the build left no $out"
ok "built from $tag"

begin sign
manifests=("$out"/*.manifest)
for m in "${manifests[@]}"; do
  echo "  ${m##*/}"
  # Prehashed (ED) is minisign's default; never -l.
  minisign -S -s "$key" -m "$m" || fail "minisign did not sign $m"
  case $(sed -n 2p "$m.minisig") in RU[Q-T]*) ;; *) fail "$m.minisig is no prehashed signature (ED)" ;; esac
done
ok "${#manifests[@]} manifests signed, prehashed"

begin verify
env -u RECIPES_PUB bin/build-release.sh --verify "$version" "$min_helper" "${providers[@]}" | sed 's/^/  /' || fail "the release does not verify"
ok "verified against minisign.pub ($pub_id)"

begin publish
files=()
for f in "$out"/*; do files+=("$f"); done
printf '  %s\n' "${files[@]##*/}"
read -r -p "  Publish these as $REPO $tag, \"$title\"? Releases are immutable: this can't be undone. [y/N] " answer
[ "$answer" = y ] || fail "not published"
# The folder or the tag can move while the question waits: check them again before anything goes up.
[ "$(git rev-parse HEAD)" = "$head" ] || fail "the folder moved off $(git rev-parse --short "$head") since the checks: run it again"
[ "$(remote_tag)" = "$tagged" ] || fail "$tag on GitHub changed since the checks"
[ "$(api_status "repos/$REPO/releases/tags/$tag")" = 404 ] || fail "a release $tag appeared since the checks"
published=1 # from here a failure may leave a release
gh release create "$tag" "${files[@]}" -R "$REPO" --verify-tag --title "$title" \
  --notes "Signed with the recipes key $pub_id. Needs eeploi-helper $min_helper." || fail "gh release create failed"
ok "published $tag"

begin 'check after'
mkdir "$work/down"
gh release download "$tag" -R "$REPO" -D "$work/down" || fail "could not download $tag again"
diff <(cd "$out" && ls -1) <(cd "$work/down" && ls -1) >/dev/null || fail "the release holds other files than $out"
for f in "${files[@]}"; do
  cmp -s "$f" "$work/down/${f##*/}" || fail "the published ${f##*/} is not the file built"
done
for m in "${manifests[@]}"; do
  minisign -V -H -q -p minisign.pub -m "$work/down/${m##*/}" -x "$work/down/${m##*/}.minisig" ||
    fail "the published ${m##*/}.minisig does not verify against minisign.pub"
done
IFS=$'\t' read -r got_title immutable < <(gh release view "$tag" -R "$REPO" --json name,isImmutable --jq '[.name, (.isImmutable | tostring)] | @tsv')
[ "$got_title" = "$title" ] || fail "the release is titled $got_title, not $title"
[ "$immutable" = true ] || fail "the release $tag is not immutable"
ok "${#files[@]} files the same as the build, signatures verify against minisign.pub, immutable"

printf '\nDone: %s, %s = %s, titled "%s".\n' "$REPO" "$tag" "$(git rev-parse --short "$tagged")" "$title"
