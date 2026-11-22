#!/usr/bin/env bash
# The one release command: checks, builds from the tag, signs with the recipes key, verifies,
# publishes the GitHub release and checks what went up. It stops on the first failure.
# D-2: signed in the maintainer's own terminal, never unattended.
# Run it yourself, in your own terminal: minisign asks for the key password, which is never
# stored, passed in or logged. Releases are immutable: step 5 asks before it publishes.
# --check runs step 1 only: no key, no build, nothing published.
# The secret key is ~/.minisign/eeploi-recipes.key, or RECIPES_KEY when set; its public key must
# be next to it (.pub) and the same as minisign.pub.
# Usage: bin/release.sh [--check] VERSION MIN_HELPER PROVIDER...   such as bin/release.sh 0.4.3 1.1.0 example
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
    echo "Stopped at step $step of $STEPS: $tag may be published, or left as a draft. Look: gh release list -R $REPO" >&2
  elif [ "$step" -gt 0 ]; then
    echo "Stopped at step $step of $STEPS: nothing was published." >&2
  fi
  exit 1
}
begin() { step=$((step + 1)); printf '\nStep %s of %s: %s\n' "$step" "$STEPS" "$1"; }
ok() { echo "  ✓ $*"; }
# Any other command that fails stops here too, with the step it stopped at.
trap 'fail "line $LINENO failed"' ERR
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
  git ls-remote origin "refs/tags/$tag" "refs/tags/$tag^{}" |
    awk -v t="refs/tags/$tag^{}" 'NR == 1 { plain = $1 } $2 == t { peeled = $1 } END { print (peeled != "" ? peeled : plain) }'
}
# gh_has <path>: true when GitHub has it, false when not (404); anything else stops.
gh_has() {
  gh api "$1" --silent 2>"$work/api" && return
  grep -q 'HTTP 404' "$work/api" || fail "GitHub did not answer for $1: $(cat "$work/api")"
  return 1
}
# release_exists: a release for $tag, a draft too (the tag lookup doesn't find drafts).
release_exists() {
  local ids
  ids=$(gh api "repos/$REPO/releases?per_page=100" --paginate --jq ".[] | select(.tag_name == \"$tag\") | .id") ||
    fail "GitHub did not list the releases of $REPO"
  [ -n "$ids" ]
}
# tag_list local|remote: each v* tag and its commit, sorted. The build reads every v* tag for
# the versions in the manifest, so they must be GitHub's.
tag_list() {
  if [ "$1" = local ]; then
    git for-each-ref --format='%(refname)' 'refs/tags/v*' | while IFS= read -r ref; do
      echo "${ref#refs/tags/} $(git rev-parse "$ref^{commit}")"
    done
  else
    git ls-remote --tags origin 'v*' | awk '{ sub("^refs/tags/", "", $2) }
      $2 ~ /\^\{\}$/ { sub("\\^\\{\\}$", "", $2); peeled[$2] = $1; next } { plain[$2] = $1 }
      END { for (t in plain) print t, (t in peeled ? peeled[t] : plain[t]) }'
  fi | sort
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
helper_ok=; if gh_has "repos/$HELPER_REPO/releases/tags/v$min_helper"; then helper_ok=1; fi
release_found=; if release_exists; then release_found=1; fi
immutable_on=$(gh api "repos/$REPO/immutable-releases" --jq .enabled) || fail "GitHub did not say whether $REPO has immutable releases"
tag_list local > "$work/tags.local"
tag_list remote > "$work/tags.remote" || fail "could not list the tags on GitHub"
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
printf '  helper   needs %s (%s)\n' "$min_helper" "$([ -n "$helper_ok" ] && echo 'released ✓' || echo 'NOT released')"
printf '  targets  %s on %s\n' "${providers[*]}" "${oses[*]:-?}"
printf '  key      %s (%s)\n' "${key/#$HOME/~}" "${key_pub_id:-no .pub next to it}"
printf '  release  %s, titled %s\n' "$([ -z "$release_found" ] && echo new || echo 'EXISTS')" "$title"

begin checks
[ "$branch" = main ] || fail "not on main"
[ -n "$clean" ] || fail "uncommitted changes"
[ -n "$synced" ] || fail "main is not the same as GitHub's main: pull or push first"
ok "on main at $(git rev-parse --short "$head"), clean, the same as GitHub"
[ -n "$tagged" ] || fail "$tag is no tag here: fetch the tags, or tag the release commit first"
[ "$remote_tagged" = "$tagged" ] || fail "$tag is not on GitHub as $(git rev-parse --short "$tagged") (GitHub: ${remote_tagged:-no such tag})"
git merge-base --is-ancestor "$tagged" origin/main || fail "$tag is not on main"
ok "$tag = $(git rev-parse --short "$tagged"), the same on GitHub, on main"
diff "$work/tags.local" "$work/tags.remote" | sed -n 's/^</  here only or other:/p; s/^>/  GitHub only or other:/p' >&2 || true
cmp -s "$work/tags.local" "$work/tags.remote" || fail "the v* tags here are not GitHub's (above): git fetch --tags, or remove a local one"
ok "every v* tag the same as GitHub's"
ci=$(gh run list -R "$REPO" --commit "$tagged" --workflow ci.yml --event push --json status,conclusion --jq '.[0] | "\(.status) \(.conclusion)"')
[ "$ci" = "completed success" ] || fail "CI on $tag is not green (${ci:-no run})"
ok "CI on $tag green"
[ -n "$helper_ok" ] || fail "no eeploi-helper release v$min_helper"
ok "eeploi-helper v$min_helper released"
[ "${#oses[@]}" -gt 0 ] || fail "$tag has no ubuntu-* folder"
# The secret key's id can't be read without its password; its public key next to it must be
# minisign.pub, and step 3 checks the signatures against minisign.pub.
case "$key" in /*) ;; *) fail "RECIPES_KEY must be an absolute path: $key" ;; esac
[ -f "$key" ] || fail "no secret key at $key (set RECIPES_KEY to use another)"
[ -f "$key_pub" ] || fail "no public key at $key_pub next to the secret key"
[ "$(sed -n 2p "$key_pub")" = "$(sed -n 2p minisign.pub)" ] || fail "$key_pub ($key_pub_id) is not minisign.pub ($pub_id)"
ok "key $key_pub_id, the same as minisign.pub"
[ -z "$release_found" ] || fail "$REPO already has a release $tag, maybe a draft: releases are immutable"
ok "no release $tag yet, no draft either"
[ "$immutable_on" = true ] || fail "$REPO does not have immutable releases on"
ok "immutable releases on"
[ ! -e "$out" ] || fail "$out exists from an earlier run: remove it first (rm -r $out)"
ok "$out is free"
if [ -n "$check_only" ]; then
  printf '\nChecks passed. Nothing built or published (--check).\n'
  exit 0
fi
[ -t 0 ] || fail "run this in your own terminal: minisign asks for the key password"

begin build
bin/build-release.sh "$version" "$min_helper" "${providers[@]}" | sed 's/^/  /' || fail "the build failed"
ok "built from $tag"

begin sign
manifests=("$out"/*.manifest)
for m in "${manifests[@]}"; do
  echo "  ${m##*/}"
  # Prehashed (ED), never -l: -H asks for it, also where it is not the default.
  minisign -S -H -s "$key" -m "$m" || fail "minisign did not sign $m"
done
ok "${#manifests[@]} manifests signed"

begin verify
env -u RECIPES_PUB bin/build-release.sh --verify "$version" "$min_helper" "${providers[@]}" | sed 's/^/  /' || fail "the release does not verify"
ok "verified against minisign.pub ($pub_id)"

begin publish
files=("$out"/*)
printf '  %s\n' "${files[@]##*/}"
read -r -p "  Publish these as $REPO $tag, \"$title\"? Releases are immutable: this can't be undone. [y/N] " answer || answer=
[ "$answer" = y ] || fail "not published"
# The folder or the tag can move while the question waits: check them again before anything goes up.
[ "$(git rev-parse HEAD)" = "$head" ] || fail "the folder moved off $(git rev-parse --short "$head") since the checks: run it again"
[ "$(remote_tag)" = "$tagged" ] || fail "$tag on GitHub changed since the checks"
! release_exists || fail "a release $tag appeared since the checks"
published=1 # from here a failure may leave a release
gh release create "$tag" "${files[@]}" -R "$REPO" --verify-tag --title "$title" \
  --notes "Signed with the recipes key $pub_id. Needs eeploi-helper $min_helper." || fail "gh release create failed"
ok "published $tag"

begin 'check after'
mkdir "$work/down"
gh release download "$tag" -R "$REPO" -D "$work/down" || fail "could not download $tag again"
# The same checks as step 4, on what went up: the files a fresh build from the tag makes, and
# signatures that verify against minisign.pub.
env -u RECIPES_PUB RECIPES_DIR="$work/down" bin/build-release.sh --verify "$version" "$min_helper" "${providers[@]}" | sed 's/^/  /' ||
  fail "the published release does not verify"
IFS=$'\t' read -r got_title immutable < <(gh release view "$tag" -R "$REPO" --json name,isImmutable --jq '[.name, (.isImmutable | tostring)] | @tsv') ||
  fail "could not read $tag back from GitHub"
[ "$got_title" = "$title" ] || fail "the release is titled $got_title, not $title"
[ "$immutable" = true ] || fail "the release $tag is not immutable"
ok "the published files verify as in step 4, titled $title, immutable"

printf '\nDone: %s, %s = %s, titled "%s".\n' "$REPO" "$tag" "$(git rev-parse --short "$tagged")" "$title"
