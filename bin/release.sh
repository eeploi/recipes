#!/usr/bin/env bash
# The one release command: checks, builds from main's head, signs with the recipes key, verifies,
# publishes the GitHub release from a checked draft and checks what went up. It stops on the first
# failure.
# D-2: signed in the maintainer's own terminal, never unattended.
# Run it yourself, in your own terminal: minisign asks for the key password, which is never
# stored, passed in or logged. Releases are immutable: step 5 asks before anything goes up.
# --check runs step 1 only: no key, no build, nothing published.
# The secret key is ~/.minisign/eeploi-recipes.key, or RECIPES_KEY when set; its public key must
# be next to it (.pub) and the same as minisign.pub.
# It takes no values: the version, the helper and the providers come from main's head
# (bin/release-values.sh, D-26).
# Usage: bin/release.sh [--check]
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

REPO=eeploi/recipes
HELPER_REPO=eeploi/helper
STEPS=8
key=${RECIPES_KEY:-$HOME/.minisign/eeploi-recipes.key}
check_only=
[ "${1:-}" != --check ] || { check_only=1; shift; }
[ "$#" -eq 0 ] || { echo "Usage: bin/release.sh [--check]: the version, helper and providers come from main's head" >&2; exit 2; }
# shellcheck source=bin/release-values.sh
. bin/release-values.sh

step=0
drafted=
published=
# While a draft may be on GitHub, $left says so and how to delete it: every failure then ends with it,
# also one that stops without fail() (Ctrl-C).
left=
work=$(mktemp -d)
trap '[ "$?" -eq 0 ] || [ -z "$left" ] || printf "release: stopped: %s\n" "$left" >&2; rm -rf "$work"' EXIT
fail() {
  echo "release: $*${left:+: $left}" >&2
  left=
  if [ -n "$published" ]; then
    echo "Stopped at step $step of $STEPS: $tag is published, the version is released." >&2
  elif [ -n "$drafted" ]; then
    echo "Stopped at step $step of $STEPS." >&2
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
# release_state: sets $release to published, draft or nothing for $tag. The tag lookup doesn't find
# drafts, and a draft has no tag yet: the list does.
release_state() {
  local states
  states=$(gh api "repos/$REPO/releases?per_page=100" --paginate \
    --jq ".[] | select(.tag_name == \"$tag\") | if .draft then \"draft\" else \"published\" end") ||
    fail "GitHub did not list the releases of $REPO"
  case $states in *published*) release=published ;; *draft*) release=draft ;; *) release= ;; esac
}
# assets <files...>: their names, sorted, comma separated, as release_view prints them.
assets() { printf '%s\n' "${@##*/}" | sort | paste -sd , -; }
# release_view <field>: "<isDraft> <field> <asset names, as assets prints them> <title>" of release $tag.
release_view() {
  gh release view "$tag" -R "$REPO" --json "isDraft,$1,assets,name" \
    --jq "\"\\(.isDraft) \\(.$1) \\([.assets[].name] | sort | join(\",\")) \\(.name)\""
}
# newer <a> <b>: version a is higher than b, each part compared as a number.
newer() {
  local IFS=. a b i
  read -r -a a <<< "$1"
  read -r -a b <<< "$2"
  for i in 0 1 2; do
    [ "$((10#${a[i]}))" -eq "$((10#${b[i]}))" ] || { [ "$((10#${a[i]}))" -gt "$((10#${b[i]}))" ]; return; }
  done
  return 1
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

# verify <folder>: what bin/build-release.sh --verify checks, on that folder: exactly the files a fresh
# build from the checked commit makes, the same bytes, and a .minisig per manifest that verifies
# against minisign.pub, prehashed only (D-1).
verify() {
  env -u RECIPES_PUB RECIPES_COMMIT="$head" RECIPES_DIR="$1" bin/build-release.sh --verify "$version" "$min_helper" "${providers[@]}" |
    sed 's/^/  /'
}
# same <folder>: it holds the files built and signed in $out, byte for byte, the .minisig files too.
# verify then checks them again on their own, against a fresh build and minisign.pub.
same() {
  local f
  for f in "${files[@]}"; do
    cmp -s "$f" "$1/${f##*/}" || { echo "  ${f##*/} differs" >&2; return 1; }
  done
}

for cmd in git gh minisign base64 od paste; do
  command -v "$cmd" >/dev/null || fail "$cmd is not installed"
done

# What the header shows, read first: nothing changes but the fetch of main.
git fetch -q origin main
branch=$(git branch --show-current)
head=$(git rev-parse HEAD)
short=$(git rev-parse --short "$head")
# D-26: the version, the helper and the providers, from the commit released, never from arguments.
from_head() { git show "$head:$1" > "$work/$2" 2>/dev/null || fail "no $1 at $short"; }
from_head CHANGELOG.md changelog
version=$(changelog_version "$work/changelog") || fail "CHANGELOG.md: $version"
from_head .github/workflows/ci.yml ci.yml
min_helper=$(helper_tag "$work/ci.yml") || fail ".github/workflows/ci.yml: $min_helper"
from_head providers providers
list=$(providers_list "$work/providers") || fail "providers: $list"
providers=()
while IFS= read -r provider; do providers+=("$provider"); done <<< "$list"
tag=v$version
title="eeploi-recipes $version"
out=dist/$version
undo="check it with gh release view $tag -R $REPO, delete it with gh release delete $tag -R $REPO, then run this again"
clean=; [ -n "$(git status --porcelain)" ] || clean=1
synced=; [ "$head" != "$(git rev-parse origin/main)" ] || synced=1
tagged=$(git rev-parse -q --verify "refs/tags/$tag^{commit}" || true)
remote_tagged=$(remote_tag) || fail "could not ask GitHub for $tag"
helper_ok=; if gh_has "repos/$HELPER_REPO/releases/tags/v$min_helper"; then helper_ok=1; fi
release_state
immutable_on=$(gh api "repos/$REPO/immutable-releases" --jq .enabled) || fail "GitHub did not say whether $REPO has immutable releases"
tag_list local > "$work/tags.local"
tag_list remote > "$work/tags.remote" || fail "could not list the tags on GitHub"
pub_id=$(key_id minisign.pub)
key_pub=${key%.key}.pub
key_pub_id=; [ ! -f "$key_pub" ] || key_pub_id=$(key_id "$key_pub")
oses=()
while IFS= read -r os; do oses+=("$os"); done < <(git ls-tree --name-only "$head" | grep '^ubuntu-' || true)

printf 'Recipes release %s\n' "$version"
printf '  repo     %s, on %s, %s%s\n' "$REPO" "${branch:-no branch}" \
  "$([ -n "$synced" ] && echo 'up to date' || echo 'NOT the same as GitHub')" "$([ -n "$clean" ] || echo ', uncommitted changes')"
printf '  commit   %s, tagged %s when published\n' "$short" "$tag"
if [ -n "$tagged$remote_tagged" ]; then
  printf '  tag      %s EXISTS%s%s\n' "$tag" "${tagged:+ here}" "${remote_tagged:+ on GitHub}"
fi
printf '  helper   needs %s (%s)\n' "$min_helper" "$([ -n "$helper_ok" ] && echo 'released ✓' || echo 'NOT released')"
printf '  targets  %s on %s\n' "${providers[*]}" "${oses[*]:-?}"
printf '  key      %s (%s)\n' "${key/#$HOME/~}" "${key_pub_id:-no .pub next to it}"
case $release in published) found=EXISTS ;; draft) found='a DRAFT exists' ;; *) found=new ;; esac
printf '  release  %s, titled %s\n' "$found" "$title"

begin checks
[ "$branch" = main ] || fail "not on main"
[ -n "$clean" ] || fail "uncommitted changes"
[ -n "$synced" ] || fail "main is not the same as GitHub's main: pull or push first"
ok "on main at $short, clean, the same as GitHub"
diff "$work/tags.local" "$work/tags.remote" | sed -n 's/^</  here only or other:/p; s/^>/  GitHub only or other:/p' >&2 || true
cmp -s "$work/tags.local" "$work/tags.remote" || fail "the v* tags here are not GitHub's (above): git fetch --tags, or remove a local one"
ok "every v* tag the same as GitHub's"
# D-21: a v* tag can't move and a release can't change, so a version is released once. Publishing
# makes the tag: until then there is none.
[ -z "$tagged$remote_tagged" ] || fail "$tag already exists: releases are immutable, release a new version"
ok "$tag is new, here and on GitHub"
# Releases only go up: no fix for an older line, which servers refuse anyway. The tags here are
# GitHub's (above).
highest=$(sed -n 's/^v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\) .*/\1/p' "$work/tags.local" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)
if [ -n "$highest" ]; then
  ! newer "$highest" "$version" || fail "$version is lower than $highest: releases only go up"
  newer "$version" "$highest" || fail "$version is not higher than $highest: releases only go up"
  ok "$version is higher than $highest, the highest v* tag"
fi
# A draft has no tag and can still go: what a run that stopped before publishing leaves.
[ "$release" != draft ] || fail "$REPO has a draft release $tag, left by a run that stopped: $undo"
[ "$release" != published ] || fail "$REPO already has a release $tag: releases are immutable, release a new version"
ok "no release $tag yet, no draft either"
ci=$(gh run list -R "$REPO" --commit "$head" --workflow ci.yml --event push --branch main --json status,conclusion --jq '.[0] | "\(.status) \(.conclusion)"')
[ "$ci" = "completed success" ] || fail "CI on main at $short is not green (${ci:-no run})"
ok "CI on main at $short green"
[ -n "$helper_ok" ] || fail "no eeploi-helper release v$min_helper"
ok "eeploi-helper v$min_helper released"
[ "${#oses[@]}" -gt 0 ] || fail "main has no ubuntu-* folder"
# The secret key's id can't be read without its password; its public key next to it must be
# minisign.pub, and step 3 checks the signatures against minisign.pub.
case "$key" in /*) ;; *) fail "RECIPES_KEY must be an absolute path: $key" ;; esac
[ -f "$key" ] || fail "no secret key at $key (set RECIPES_KEY to use another)"
[ -f "$key_pub" ] || fail "no public key at $key_pub next to the secret key"
[ "$(sed -n 2p "$key_pub")" = "$(sed -n 2p minisign.pub)" ] || fail "$key_pub ($key_pub_id) is not minisign.pub ($pub_id)"
ok "key $key_pub_id, the same as minisign.pub"
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
RECIPES_COMMIT=$head bin/build-release.sh "$version" "$min_helper" "${providers[@]}" | sed 's/^/  /' || fail "the build failed"
ok "built from main at $short"

begin sign
manifests=("$out"/*.manifest)
for m in "${manifests[@]}"; do
  echo "  ${m##*/}"
  # Prehashed (ED), never -l: -H asks for it, also where it is not the default.
  minisign -S -H -s "$key" -m "$m" || fail "minisign did not sign $m"
done
ok "${#manifests[@]} manifests signed"

begin verify
verify "$out" || fail "the release does not verify"
ok "verified against minisign.pub ($pub_id)"

begin draft
files=("$out"/*)
want=$(assets "${files[@]}")
printf '  %s\n' "${files[@]##*/}"
read -r -p "  Publish these as $REPO $tag, \"$title\"? It goes up as a draft first, checked before it is published. Once published, it can't be undone. [y/N] " answer || answer=
[ "$answer" = y ] || fail "not published"
# The folder or GitHub can change while the question waits: check them again before anything goes up.
[ "$(git rev-parse HEAD)" = "$head" ] || fail "the folder moved off $short since the checks: run it again"
git fetch -q origin main
[ "$(git rev-parse origin/main)" = "$head" ] || fail "GitHub's main moved off $short since the checks: run it again"
tag_list remote > "$work/tags.now" || fail "could not list the tags on GitHub"
cmp -s "$work/tags.local" "$work/tags.now" || fail "the v* tags on GitHub changed since the checks: run it again"
remote=$(remote_tag) || fail "could not ask GitHub for $tag"
[ -z "$remote" ] || fail "$tag was made on GitHub since the checks: release a new version"
release_state
[ -z "$release" ] || fail "a release $tag appeared since the checks"
# D-21: nothing that can't change goes up before its files are checked. The release starts as a
# draft, with no tag; publishing it in step 7 makes the tag on the checked commit. Until then a
# failure leaves only a draft, which can be deleted, and the version stays free.
drafted=1
left="nothing was published and $tag was not made. A draft release $tag may be left on GitHub: $undo"
gh release create "$tag" "${files[@]}" -R "$REPO" --draft --target "$head" --title "$title" \
  --notes "Signed with the recipes key $pub_id. Needs eeploi-helper $min_helper." > /dev/null || fail "could not create the draft"
ok "draft $tag on $short, no tag yet"

begin 'verify the draft'
draft=$(release_view targetCommitish) || fail "could not read the draft"
[ "$draft" = "true $head $want $title" ] ||
  fail "the draft is not a draft on $short titled $title with only the files built and signed ($draft)"
mkdir "$work/draft"
gh release download "$tag" -R "$REPO" -D "$work/draft" || fail "could not download the draft's files"
same "$work/draft" || fail "the draft's files are not the ones built and signed"
verify "$work/draft" || fail "the draft does not verify"
ok "the draft holds the files built and signed, byte for byte, and verifies against minisign.pub"

begin publish
# A tag made on GitHub since the checks would carry the release: stop while it is a draft.
remote=$(remote_tag) || fail "could not ask GitHub for $tag"
if [ -n "$remote" ]; then
  left=
  fail "$tag was made on GitHub since the checks, so this version can't be released: the draft was not published;" \
    "delete it with gh release delete $tag -R $REPO and release a new version"
fi
if ! gh release edit "$tag" -R "$REPO" --draft=false > /dev/null; then
  # The error can come after GitHub published it: only a release that is still a draft is unpublished.
  state=$(gh release view "$tag" -R "$REPO" --json isDraft --jq .isDraft 2>"$work/view") || state=$(cat "$work/view")
  [ "$state" != true ] || fail "could not publish the draft"
  left=
  [ "$state" != false ] || { published=1; fail "publishing $tag gave an error, but GitHub shows it published: check gh release view $tag -R $REPO before anything else"; }
  fail "publishing $tag gave an error, and GitHub could not say whether it is published ($state): check gh release view $tag -R $REPO." \
    "Still a draft: $undo. Published: the version is released"
fi
left=
published=1
ok "published $tag"

begin 'check after'
got=$(release_view isImmutable) || fail "could not read $tag back from GitHub"
[ "$got" = "false true $want $title" ] ||
  fail "$tag is published, but not as an immutable release titled $title with only the files built and signed ($got): check it and the repository's settings"
# A draft's files could still change until it was published: check the published ones too.
mkdir "$work/down"
gh release download "$tag" -R "$REPO" -D "$work/down" || fail "could not download $tag again"
same "$work/down" || fail "the published files are not the ones built and signed"
verify "$work/down" || fail "the published release does not verify"
git fetch -q origin "refs/tags/$tag:refs/tags/$tag" || fail "could not fetch $tag from GitHub"
[ "$(git rev-parse "refs/tags/$tag^{commit}")" = "$head" ] || fail "$tag on GitHub is not $short"
ok "immutable, titled $title, the files built and signed, verified again; $tag on $short"

printf '\nDone: %s, %s = %s, titled "%s".\n' "$REPO" "$tag" "$short" "$title"
