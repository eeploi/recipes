#!/usr/bin/env bash
# Tests bin/release.sh against a fake GitHub, so no real release, tag or draft is made: a copy of
# the working tree in a repo of its own with a local origin, a gh stub, and minisign with a test key
# without a password. The stub keeps the release in $GH_STATE/release ("<draft> <commit>", true for
# a draft) and its files in $GH_STATE/assets; publishing makes the tag in the origin, lightweight,
# as GitHub does. GH_FAIL: create (the draft is made, its files don't upload), extra (a file more),
# corrupt or badsig (what a download gives), tagrace (a tag made on GitHub during the download),
# publish (the draft stays), noview (publish, and GitHub can't be asked after), late (published,
# then an error), swap (a file changed while it was a draft, seen once published). GH_IMMUTABLE=false:
# the published release is not immutable. GH_RUNS and GH_RUN: the JSON GitHub gives for CI's runs on
# the commit and for the run, through the script's own --jq (default: one run, on the head, each job
# passed). GH_HELPER: the helper release GitHub has; GH_FAIL=helperkey: its files signed with another key.
# bin/release.sh takes no values: the copy's CHANGELOG.md says 9.9.9, its providers file example, and
# its ci.yml's HELPER_TAG v1.2.3. Each refused value is a commit of its own, not pushed: the values
# are read before main is compared with GitHub's.
# Also bin/build-release.sh with RECIPES_COMMIT: the same bytes as from a tag on that commit.
# Needs git, jq, minisign, script and timeout. Runs without GitHub: CI runs it, and so can you.
set -euo pipefail
export LC_ALL=C
root=$(cd "$(dirname "$0")/.." && pwd)
for cmd in git jq minisign script timeout; do
  command -v "$cmd" >/dev/null || { echo "test-release: $cmd is not installed" >&2; exit 1; }
done

t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
repo=$t/repo
mkdir -p "$t/stubs" "$t/gh" "$repo"
failed=0
pass() { echo "ok: $1"; }
failure() { echo "FAIL: $1"; printf '%s\n' "$2" | sed 's/^/  /'; failed=$((failed + 1)); }

cat > "$t/stubs/gh" << 'EOF'
#!/usr/bin/env bash
s=$GH_STATE
echo "$*" >> "$s/log"
case "$1 $2" in
  "api repos/eeploi/helper/releases/tags/"*)
    [ "$2" = "repos/eeploi/helper/releases/tags/v${GH_HELPER:-1.2.3}" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; } ;;
  "api repos/eeploi/recipes/releases?per_page=100")
    [ -f "$s/release" ] || exit 0
    read -r draft _ < "$s/release"
    if [ "$draft" = true ]; then echo draft; else echo published; fi ;;
  "api repos/eeploi/recipes/immutable-releases") echo true ;;
  "run list" | "run view")
    # The script's own --jq on what GitHub gives.
    jq= sub=$2
    while [ $# -gt 0 ]; do [ "$1" != --jq ] || jq=$2; shift; done
    sha=$(git rev-parse HEAD)
    if [ "$sub" = list ]; then json=${GH_RUNS-'[{"databaseId":42}]'}; else
      jobs='{"name":"check","status":"completed","conclusion":"success"},{"name":"server (8.5)","status":"completed","conclusion":"success"},{"name":"server (8.4)","status":"completed","conclusion":"success"}'
      json=${GH_RUN-"{\"headSha\":\"$sha\",\"status\":\"completed\",\"conclusion\":\"success\",\"jobs\":[$jobs]}"}
    fi
    jq -r "$jq" <<< "$json" ;;
  "release view")
    [ "${GH_FAIL:-}" != noview ] || [ ! -f "$s/tried" ] || { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
    [ -f "$s/release" ] || { echo "release not found" >&2; exit 1; }
    read -r draft target < "$s/release"
    assets=$(ls "$s/assets" | paste -sd , -)
    case "$*" in
      *"--jq .isDraft") echo "$draft" ;;
      *isDraft,targetCommitish,assets,name*) echo "$draft $target $assets $(cat "$s/title")" ;;
      *isDraft,isImmutable,assets,name*) echo "$draft ${GH_IMMUTABLE:-true} $assets $(cat "$s/title")" ;;
      *) exit 1 ;;
    esac ;;
  "release create")
    tag=$3
    shift 3
    files=()
    while [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; do files+=("$1"); shift; done
    [[ " $* " == *" --draft "* ]] || exit 1
    target=
    while [ $# -gt 0 ]; do
      case $1 in --target) target=$2 ;; --title) echo "$2" > "$s/title" ;; esac
      shift
    done
    mkdir -p "$s/assets"
    echo "true $target" > "$s/release"
    [ "${GH_FAIL:-}" != create ] || exit 1
    cp "${files[@]}" "$s/assets/"
    [ "${GH_FAIL:-}" != extra ] || echo notes > "$s/assets/notes.txt" ;;
  "release download")
    dir=
    for a in "$@"; do [ "${prev:-}" != -D ] || dir=$a; prev=$a; done
    if [[ " $* " == *" -R eeploi/helper "* ]]; then
      [ "$3" = "v${GH_HELPER:-1.2.3}" ] || { echo "release not found" >&2; exit 1; }
      mkdir -p "$dir"
      if [ "${GH_FAIL:-}" = helperkey ]; then cp "$GH_HELPERS"/other/* "$dir/"; else cp "$GH_HELPERS"/signed/* "$dir/"; fi
      exit 0
    fi
    mkdir -p "$dir"
    cp "$s"/assets/* "$dir/"
    case "${GH_FAIL:-}" in
      corrupt) echo changed >> "$(ls "$dir"/*.tar.gz)" ;;
      badsig) for f in "$dir"/*.minisig; do echo changed >> "$f"; done ;;
      tagrace) read -r _ target < "$s/release"; git --git-dir="$GH_ORIGIN" update-ref "refs/tags/$GH_TAG" "$target" ;;
    esac ;;
  "release edit")
    [ "$4 $5 $6 $#" = "-R eeploi/recipes --draft=false 6" ] || exit 1
    : > "$s/tried"
    [ "${GH_FAIL:-}" != publish ] && [ "${GH_FAIL:-}" != noview ] || exit 1
    read -r _ target < "$s/release"
    echo "false $target" > "$s/release"
    git --git-dir="$GH_ORIGIN" update-ref "refs/tags/$GH_TAG" "$target"
    [ "${GH_FAIL:-}" != swap ] || echo changed >> "$(ls "$s"/assets/*.tar.gz)"
    [ "${GH_FAIL:-}" != late ] || exit 1 ;;
  *) echo "gh stub: $*" >&2; exit 1 ;;
esac
EOF
chmod 755 "$t/stubs/gh"

minisign -G -W -p "$t/key.pub" -s "$t/key.key" >/dev/null
# The helper release GitHub gives: eeploi-helper 1.2.3, signed with a helper test key, the copy's
# HELPER_PUBKEY; and the same file signed with another key (GH_FAIL=helperkey).
mkdir -p "$t/helpers/signed" "$t/helpers/other"
for k in helper other; do
  minisign -G -W -p "$t/$k.pub" -s "$t/$k.key" >/dev/null
  d=signed; [ "$k" = helper ] || d=other
  printf "#!/bin/sh\nVERSION='1.2.3'\n" > "$t/helpers/$d/eeploi-helper"
  minisign -S -H -s "$t/$k.key" -m "$t/helpers/$d/eeploi-helper" >/dev/null
done
# git without the user's own config (signing, hooks), and never on the real repo (GIT_DIR from a hook, say).
env_=(-u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u RECIPES_COMMIT -u RECIPES_DIR -u RECIPES_PUB
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GH_STATE="$t/gh" GH_ORIGIN="$t/origin.git" GH_TAG=v9.9.9 GH_HELPERS="$t/helpers" NO_COLOR=1
  PATH="$t/stubs:$PATH" RECIPES_KEY="$t/key.key")
tgit() { env "${env_[@]}" git -c user.name=Test -c user.email=test@example.com "$@"; }

# The tracked files as they are now, with the test key as minisign.pub, version 9.9.9 and provider example.
git -C "$root" ls-files -z | (cd "$root" && tar --null -T - -cf -) | tar -xf - -C "$repo"
cp "$t/key.pub" "$repo/minisign.pub"
printf '# Changelog\n\n## Unreleased\n\n## 9.9.9\n\n- A test.\n\n## 9.9.8\n' > "$repo/CHANGELOG.md"
printf '# A comment\n\nexample\n' > "$repo/providers"
helper=1.2.3
sed -i.bak -e "s/^  HELPER_TAG: .*/  HELPER_TAG: v$helper/" \
  -e "s|^  HELPER_PUBKEY: .*|  HELPER_PUBKEY: $(sed -n 2p "$t/helper.pub")|" "$repo/.github/workflows/ci.yml"
rm "$repo/.github/workflows/ci.yml.bak"
tgit init -q --bare "$t/origin.git"
tgit -C "$repo" init -q -b main
tgit -C "$repo" add -A
tgit -C "$repo" commit -qm one
tgit -C "$repo" remote add origin "$t/origin.git"
tgit -C "$repo" push -q origin main
head=$(tgit -C "$repo" rev-parse HEAD)
short=$(tgit -C "$repo" rev-parse --short HEAD)
undo="check it with gh release view v9.9.9 -R eeploi/recipes, delete it with gh release delete v9.9.9 -R eeploi/recipes, then run this again"
args=(9.9.9 "$helper" example) # what bin/release.sh reads from the copy, for bin/build-release.sh

# expect <exit code> <name> <expected output>: on $code and $out of a run.
expect() {
  if [ "$code" -eq "$1" ] && [[ $out == *"$3"* ]]; then pass "$2"; else failure "$2" "exit $code, expected $1 and: $3
$out"; fi
}
check() { local name=$1; shift; if "$@"; then pass "$name"; else failure "$name" "$*"; fi; }
# reset: no draft, no release, no v9.9.9 and no build: what deleting a draft leaves too.
reset() {
  rm -rf "$t/gh" "$repo/dist"
  mkdir "$t/gh"
  tgit --git-dir="$t/origin.git" update-ref -d refs/tags/v9.9.9
  tgit -C "$repo" update-ref -d refs/tags/v9.9.9
}
# checks <exit code> <name> <expected output>: bin/release.sh --check.
checks() {
  code=0
  out=$(cd "$repo" && env "${env_[@]}" bash bin/release.sh --check 2>&1) || code=$?
  expect "$@"
}
# run <answer> <exit code> <name> <expected output>: bin/release.sh in a terminal (script, util-linux
# or BSD), the answer typed at its question. The input stays open until it ends: at the end of its
# input, BSD script types an end of file before the answer. NO_COLOR is set, unless $colour.
colour=
run() {
  local answer=$1 cmd
  shift
  rm -f "$t/ended"
  cmd="bash bin/release.sh"
  [ -z "$colour" ] || cmd="env -u NO_COLOR $cmd"
  out=$({ printf '%s\n' "$answer"; while [ ! -e "$t/ended" ]; do sleep 0.1; done; } |
    { cd "$repo" && if script --version 2>/dev/null | grep -q util-linux; then
        env "${env_[@]}" timeout 60 script -qec "$cmd" /dev/null
      else
        # shellcheck disable=SC2086 # the words of $cmd
        env "${env_[@]}" timeout 60 script -q /dev/null $cmd
      fi 2>&1
      echo "$?" > "$t/ended"; } | tr -d '\r')
  read -r code < "$t/ended"
  expect "$@"
}
# draft <name>: the release is still a draft, and no v9.9.9 is here or on GitHub.
draft() {
  check "$1: still a draft" grep -q '^true ' "$t/gh/release"
  check "$1: no tag here" test -z "$(tgit -C "$repo" tag -l v9.9.9)"
  check "$1: no tag on GitHub" test -z "$(tgit --git-dir="$t/origin.git" tag -l v9.9.9)"
}
# left <mode> <name> <expected output>: with GH_FAIL=<mode> it stops while the release is a draft,
# and says so with how to delete it.
left() {
  GH_FAIL=$1 run y 1 "$2" "✗ $3: nothing was published and v9.9.9 was not made. A draft release v9.9.9 may be left on GitHub: $undo"
  draft "$2"
}

kid=$(sed -n '1s/.* //p' "$t/key.pub")
hid=$(sed -n '1s/.* //p' "$t/helper.pub")
# sha <file>: its SHA-256.
sha() { if command -v sha256sum > /dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
ci=.github/workflows/ci.yml
# sed_ci <sed script>: ci.yml in the folder it runs in, changed.
sed_ci() { sed "$1" "$ci" > "$t/ci.new" && cat "$t/ci.new" > "$ci"; }

echo "== bin/build-release.sh from a commit"
(cd "$repo" && env "${env_[@]}" RECIPES_COMMIT="$head" bin/build-release.sh "${args[@]}" >/dev/null)
mv "$repo/dist/9.9.9" "$t/from-commit"
tgit -C "$repo" tag v9.9.9
(cd "$repo" && env "${env_[@]}" bin/build-release.sh "${args[@]}" >/dev/null)
check "the build from a commit is the build from its tag, byte for byte" diff -r "$t/from-commit" "$repo/dist/9.9.9"
reset
tgit -C "$repo" tag v9.9.9 "$(tgit -C "$repo" commit-tree -m other "$head^{tree}")"
code=0
out=$(cd "$repo" && env "${env_[@]}" RECIPES_COMMIT="$head" bin/build-release.sh "${args[@]}" 2>&1) || code=$?
expect 1 "a tag of this version on another commit is refused" "v9.9.9 is on another commit than $head"
reset

echo "== bin/release.sh --check"
checks 0 "a new version passes the checks" "Every check passed. Nothing built, signed or published (--check)."
expect 0 "the overview: versions, commit, key, helper, providers" "==========================================
EEPLOI RECIPES  ·  release
==========================================
Previous version   none
New version        9.9.9
Commit             $short  main
Key                $kid
Needs helper       1.2.3   (HELPER_TAG v1.2.3)
Providers          example
==========================================

Checks
"
expect 0 "the checks, in order" "  ✓ main is clean and matches GitHub, its v* tags too
  ✓ 9.9.9 is higher than every released version
  ✓ CHANGELOG: ## 9.9.9, Unreleased empty
  ✓ helper v1.2.3 is released, and its key matches HELPER_PUBKEY ($hid)
  ✓ CI \`check\`, \`server (8.5)\`, \`server (8.4)\` passed on $short
  ✓ key $t/key.key, the same as minisign.pub
  ✓ immutable releases on, dist/9.9.9 is free
  ✓ First release: no earlier version

Every check passed."
check "no colour in a pipe" test -z "$(grep $'\033' <<< "$out" || true)"
check "the checks made nothing" test -z "$(grep -E '^release (create|edit)' "$t/gh/log")"
check "the checks built nothing" test ! -e "$repo/dist"
check "CI: the latest run of the push to main on this commit" \
  grep -qxF "run list -R eeploi/recipes --commit $head --workflow ci.yml --event push --branch main --limit 1 --json databaseId --jq .[0].databaseId // \"\"" "$t/gh/log"
echo "true $head" > "$t/gh/release"
checks 1 "a draft of this version stops the checks, with how to delete it" \
  "✗ eeploi/recipes has a draft release v9.9.9, left by a run that stopped: $undo"
echo "false $head" > "$t/gh/release"
checks 1 "a release of this version stops the checks" \
  "✗ eeploi/recipes already has a release v9.9.9: releases are immutable, release a new version"
reset
tgit --git-dir="$t/origin.git" update-ref refs/tags/v9.9.9 "$head"
tgit -C "$repo" fetch -q origin 'refs/tags/*:refs/tags/*'
checks 1 "the tag of this version stops the checks" "✗ v9.9.9 already exists: releases are immutable, release a new version"
reset
tgit --git-dir="$t/origin.git" update-ref refs/tags/v9.9.9 "$head"
checks 1 "the tag on GitHub only stops the checks" "✗ the v* tags here are not GitHub's"
reset
# Higher than every v* tag, compared as numbers: 9.10.0 is higher than 9.9.9, and 9.09.9 the same.
# The same tag is refused above.
for v in 9.10.0 9.09.9 9.9.8; do
  tgit --git-dir="$t/origin.git" update-ref "refs/tags/v$v" "$head"
  tgit -C "$repo" update-ref "refs/tags/v$v" "$head"
  case $v in
    9.10.0) checks 1 "a version lower than the highest tag stops the checks" "✗ 9.9.9 is lower than 9.10.0: releases only go up" ;;
    9.09.9) checks 1 "a version equal to the highest tag stops the checks" "✗ 9.9.9 is not higher than 9.09.9: releases only go up" ;;
    *)
      checks 0 "a version higher than the highest tag passes the checks" "  ✓ 9.9.9 is higher than every released version"
      expect 0 "the overview shows the highest tag as the previous version" "Previous version   9.9.8   (v9.9.8)"
      expect 0 "no commit since the previous version" "  ✓ Changes since v9.9.8: 0 commits, 0 server files changed" ;;
  esac
  tgit --git-dir="$t/origin.git" update-ref -d "refs/tags/v$v"
  tgit -C "$repo" update-ref -d "refs/tags/v$v"
done

echo "== bin/release.sh, CI on the commit"
# run_json <jobs> [<commit>] [<conclusion>]: what GitHub gives for the run; job <name> [<status>]
# [<conclusion, JSON>].
run_json() { printf '{"headSha":"%s","status":"completed","conclusion":"%s","jobs":[%s]}' "${2:-$head}" "${3:-success}" "$1"; }
job() { printf '{"name":"%s","status":"%s","conclusion":%s}' "$1" "${2:-completed}" "${3:-\"success\"}"; }
all="$(job check),$(job 'server (8.5)'),$(job 'server (8.4)')"
GH_RUNS='[]' checks 1 "no CI run on the commit stops the checks" "✗ CI has no run on main at $short yet"
GH_RUNS='[{"databaseId":"42; x"}]' checks 1 "a run id that is no number stops the checks" "✗ could not read CI's run on $short (42; x)"
GH_RUN=$(run_json "$all" 0000000) checks 1 "a run on another commit stops the checks" "✗ CI's run 42 is not on $short (0000000)"
GH_RUN=$(run_json "$all" "$head" failure) checks 1 "a run that failed, its named jobs passed, stops the checks" \
  "✗ CI's run 42 on $short has not passed (completed/failure)"
GH_RUN=$(run_json "$(job check),$(job 'server (8.5)')") checks 1 "a job missing stops the checks" \
  "✗ CI's run 42 on $short has no job named server (8.4)"
GH_RUN=$(run_json "$(job check),$(job 'server (8.5)'),$(job 'server (php 8.4)')") checks 1 "a job renamed stops the checks" \
  "✗ CI's run 42 on $short has no job named server (8.4)"
GH_RUN=$(run_json "") checks 1 "a run without jobs stops the checks" "✗ CI's run 42 on $short has no job named check"
GH_RUN=$(run_json "$(job check),$(job 'server (8.5)' completed '"failure"'),$(job 'server (8.4)')") checks 1 "a failed job stops the checks" \
  "✗ CI's server (8.5) job on $short has not passed (completed/failure)"
GH_RUN=$(run_json "$(job check in_progress null),$(job 'server (8.5)'),$(job 'server (8.4)')") checks 1 "a job still running stops the checks" \
  "✗ CI's check job on $short has not passed (in_progress/null)"
GH_RUN=$(run_json "$all,$(job check)") checks 1 "a job there twice stops the checks" \
  "✗ CI's check job on $short has not passed (completed/success,completed/success)"
GH_RUN=$(run_json "$(job 'check\u001b[2J' completed '"failure"'),$all") checks 0 "a job with an escape in its name is another job" "CI \`check\`"

echo "== bin/release.sh, the helper"
GH_FAIL=helperkey checks 1 "a helper release signed with another key stops the checks" \
  "✗ eeploi-helper v1.2.3 does not verify against HELPER_PUBKEY ($hid)"
# A helper version GitHub doesn't have, then one whose file says another version: pushed, so the checks
# get to it.
(cd "$repo" && sed_ci 's/^  HELPER_TAG: .*/  HELPER_TAG: v1.2.4/')
tgit -C "$repo" commit -qam "helper 1.2.4"
tgit -C "$repo" push -q origin main
checks 1 "a helper version not released stops the checks" "✗ no eeploi-helper release v1.2.4"
expect 1 "the overview shows the helper from ci.yml" "Needs helper       1.2.4   (HELPER_TAG v1.2.4)"
GH_HELPER=1.2.4 checks 1 "a helper release of another version stops the checks" "✗ eeploi-helper v1.2.4 is not VERSION='1.2.4'"
tgit -C "$repo" reset -q --hard "$head"
tgit -C "$repo" push -q -f origin main

echo "== bin/release.sh, its values from main's head"
for extra in 9.9.9 "--check 9.9.9" "9.9.9 $helper example" --verify; do
  code=0
  # shellcheck disable=SC2086 # the words of $extra
  out=$(cd "$repo" && env "${env_[@]}" bash bin/release.sh $extra 2>&1) || code=$?
  expect 2 "an argument is refused: $extra" "Usage: bin/release.sh [--check]"
done
# refused <name> <expected output> <shell code>: main's head with the code run on it, committed,
# stops the checks; then main is back at $head.
refused() {
  (cd "$repo" && eval "$3")
  tgit -C "$repo" add -A
  tgit -C "$repo" commit -qm "$1"
  checks 1 "$1" "✗ $2"
  tgit -C "$repo" reset -q --hard "$head"
}
refused "no CHANGELOG.md" "no CHANGELOG.md at" 'rm CHANGELOG.md'
refused "no version in CHANGELOG.md" "CHANGELOG.md: no ## VERSION heading after ## Unreleased" \
  "printf '# Changelog\n\n## Unreleased\n' > CHANGELOG.md"
refused "a line under ## Unreleased" "CHANGELOG.md: ## Unreleased is not empty: move its lines under a version" \
  "printf '# Changelog\n\n## Unreleased\n\n- Not released.\n\n## 9.9.9\n' > CHANGELOG.md"
refused "no ## Unreleased" "CHANGELOG.md: the first heading is not ## Unreleased" \
  "printf '# Changelog\n\n## 9.9.9\n' > CHANGELOG.md"
refused "no ## Unreleased at all" "CHANGELOG.md: no ## Unreleased heading" "printf '# Changelog\n' > CHANGELOG.md"
refused "a version heading that is no version" "CHANGELOG.md: the heading after ## Unreleased is not ## VERSION" \
  "printf '# Changelog\n\n## Unreleased\n\n## 9.9.9 (soon)\n' > CHANGELOG.md"
refused "a version with a leading zero" "CHANGELOG.md: the heading after ## Unreleased is not ## VERSION" \
  "printf '# Changelog\\n\\n## Unreleased\\n\\n## 9.09.9\\n' > CHANGELOG.md"
refused "HELPER_TAG no version" ".github/workflows/ci.yml: HELPER_TAG is not vN.N.N:   HELPER_TAG: latest" \
  "sed_ci 's/^  HELPER_TAG: .*/  HELPER_TAG: latest/'"
refused "HELPER_TAG with more after it" ".github/workflows/ci.yml: HELPER_TAG is not vN.N.N" \
  "sed_ci 's/^  HELPER_TAG: .*/& # v9.0.0/'"
refused "HELPER_TAG with a leading zero" ".github/workflows/ci.yml: HELPER_TAG is not vN.N.N" \
  "sed_ci 's/^  HELPER_TAG: .*/  HELPER_TAG: v1.02.3/'"
refused "no HELPER_TAG" ".github/workflows/ci.yml: not one HELPER_TAG line" "sed_ci '/^  HELPER_TAG: /d'"
refused "HELPER_TAG twice" ".github/workflows/ci.yml: not one HELPER_TAG line" "echo '  HELPER_TAG: v9.0.0' >> $ci"
refused "no HELPER_PUBKEY" ".github/workflows/ci.yml: not one HELPER_PUBKEY line" "sed_ci '/^  HELPER_PUBKEY: /d'"
refused "HELPER_PUBKEY twice" ".github/workflows/ci.yml: not one HELPER_PUBKEY line" "echo '  HELPER_PUBKEY: RW' >> $ci"
refused "HELPER_PUBKEY no key" ".github/workflows/ci.yml: HELPER_PUBKEY is not a minisign public key" \
  "sed_ci 's/^  HELPER_PUBKEY: .*/&x/'"
refused "no providers file" "no providers at" 'rm providers'
refused "no provider" "providers: no provider" "echo '# none' > providers"
refused "a provider the helper refuses" "providers: Example is no provider name" "echo Example >> providers"
refused "a provider twice" "providers: example is there twice" "echo example >> providers"
refused "nothing under the version" "CHANGELOG.md: nothing under ## 9.9.9" \
  "printf '# Changelog\n\n## Unreleased\n\n## 9.9.9\n\n## 9.9.8\n\n- Older.\n' > CHANGELOG.md"
refused "nothing under the version, the last heading" "CHANGELOG.md: nothing under ## 9.9.9" \
  "printf '# Changelog\n\n## Unreleased\n\n## 9.9.9\n' > CHANGELOG.md"

echo "== bin/release.sh, what changed since the previous release"
tgit --git-dir="$t/origin.git" update-ref refs/tags/v9.9.8 "$head"
tgit -C "$repo" update-ref refs/tags/v9.9.8 "$head"
echo '# a change' >> "$repo/stack/start.sh"
tgit -C "$repo" commit -qam "Step 10: a change (#12)"
echo 'More words.' >> "$repo/README.md"
tgit -C "$repo" commit -qam "README: more words (#13)"
tgit -C "$repo" commit -q --allow-empty -m $'An odd \033[2J subject'
tgit -C "$repo" push -q origin main
checks 0 "a few commits: their subjects, the pull request first" "  ✓ Changes since v9.9.8: 3 commits, 1 server file changed
      #12 Step 10: a change
      #13 README: more words
      An odd [2J subject
"
check "a subject with an escape is printed without it" test -z "$(grep $'\033' <<< "$out" || true)"
echo example2 >> "$repo/providers"
echo '# a marker comment' >> "$repo/markers"
for i in 1 2 3 4 5 6; do tgit -C "$repo" commit -q --allow-empty -m "more $i"; done
tgit -C "$repo" commit -qam "more 7"
tgit -C "$repo" commit -q --allow-empty -m "more 8"
tgit -C "$repo" push -q origin main
now=$(tgit -C "$repo" rev-parse --short HEAD)
checks 0 "many commits: the count, and how to see them; markers and providers count" "  ✓ Changes since v9.9.8: 11 commits, 3 server files changed
      see them with: git log --oneline v9.9.8..$now
"
check "many commits: no subject" test -z "$(grep -F 'more 1' <<< "$out" || true)"
other=$(tgit -C "$repo" commit-tree -m other "$head^{tree}")
tgit -C "$repo" push -q -f origin "$other:refs/tags/v9.9.8"
tgit -C "$repo" update-ref refs/tags/v9.9.8 "$other"
checks 1 "a previous release not in the history stops the checks" "✗ v9.9.8 is not in the history of $now"
tgit --git-dir="$t/origin.git" update-ref -d refs/tags/v9.9.8
tgit -C "$repo" update-ref -d refs/tags/v9.9.8
tgit -C "$repo" reset -q --hard "$head"
tgit -C "$repo" push -q -f origin main

echo "== bin/release.sh"
run n 1 "no at the question" "✗ stopped: nothing built, signed or published"
expect 1 "the question names the version" "Sign 9.9.9? [y/N]"
check "no at the question: no draft" test -z "$(grep -E '^release (create|edit)' "$t/gh/log")"
check "no at the question: nothing built" test ! -e "$repo/dist/9.9.9"
reset
colour=1 run n 1 "in a terminal, in colour" "stopped: nothing built, signed or published"
check "in a terminal: a green ✓" grep -qF $'\033[32m✓\033[0m main is clean' <<< "$out"
check "in a terminal: a red ✗" grep -qF $'\033[31m✗\033[0m stopped' <<< "$out"
reset
left create "the draft's files don't upload" "could not create the draft"
check "a run that stops before publishing removes what it built" test ! -e "$repo/dist/9.9.9"
checks 1 "the draft left by a failed run stops the next one" "✗ eeploi/recipes has a draft release v9.9.9, left by a run that stopped"
reset
m=recipes-9.9.9-example-ubuntu-26.04.manifest
left extra "a file more in the draft" "the draft is not a draft on $short titled eeploi-recipes 9.9.9 with only the files built and signed (true $head notes.txt,$m,$m.minisig,recipes-9.9.9.tar.gz eeploi-recipes 9.9.9)"
reset
left corrupt "the draft's package is not the one built" "the draft's files are not the ones built and signed"
reset
left badsig "the draft's signature is not the one made" "the draft's files are not the ones built and signed"
reset
name="a tag made on GitHub since the checks"
GH_FAIL=tagrace run y 1 "$name" "✗ v9.9.9 was made on GitHub since the checks, so this version can't be released: the draft was not published; delete it with gh release delete v9.9.9 -R eeploi/recipes and release a new version"
check "$name: still a draft" grep -q '^true ' "$t/gh/release"
check "$name: no run again" test -z "$(grep -F 'run this again' <<< "$out")"
reset
left publish "publishing fails" "could not publish the draft"
reset
name="publishing fails, and GitHub can't be asked after"
GH_FAIL=noview run y 1 "$name" "✗ publishing v9.9.9 gave an error, and GitHub could not say whether it is published (HTTP 502: Bad Gateway): check gh release view v9.9.9 -R eeploi/recipes. Still a draft: $undo. Published: the version is released"
draft "$name"
reset
GH_FAIL=late run y 1 "an error after GitHub published it" \
  "✗ publishing v9.9.9 gave an error, but GitHub shows it published: check gh release view v9.9.9 -R eeploi/recipes before anything else"
reset
published="v9.9.9 is published, the version is released: check it with gh release view v9.9.9 -R eeploi/recipes"
GH_IMMUTABLE=false run y 1 "a release that is not immutable" \
  "✗ v9.9.9 is not an immutable release titled eeploi-recipes 9.9.9 with only the files built and signed (false false $m,$m.minisig,recipes-9.9.9.tar.gz eeploi-recipes 9.9.9): check it and the repository's settings: $published"
reset
GH_FAIL=swap run y 1 "a file changed before publishing, seen in the published release" \
  "✗ the published files are not the ones built and signed: $published"
reset

name="a new version"
run y 0 "$name" "  ✓ built from $short, the same bytes as from a tag on it
      $m
      recipes-9.9.9.tar.gz
  ✓ signed and verified: $m
  ✓ draft created, files match
  ✓ published: v9.9.9, immutable

==========================================
RELEASED  eeploi-recipes 9.9.9
"
for f in "$t"/gh/assets/*; do
  check "$name: the SHA-256 of ${f##*/}" grep -qxF "${f##*/}  $(sha "$f")" <<< "$out"
done
check "$name: the draft on the checked commit" grep -qE "^release create v9.9.9 .* -R eeploi/recipes --draft --target $head --title eeploi-recipes 9.9.9 --notes " "$t/gh/log"
check "$name: published after its files were checked" \
  test "$(grep -v 'eeploi/helper' "$t/gh/log" | sed -nE 's/^release (create|download|edit) .*/\1/p' | paste -sd ' ' -)" = "create download edit download"
check "$name: the only edit publishes the draft" test "$(grep '^release edit' "$t/gh/log")" = "release edit v9.9.9 -R eeploi/recipes --draft=false"
check "$name: the tag on GitHub, made by publishing, lightweight" \
  test "$(tgit --git-dir="$t/origin.git" cat-file -t refs/tags/v9.9.9) $(tgit --git-dir="$t/origin.git" rev-parse refs/tags/v9.9.9)" = "commit $head"
check "$name: the tag here too" test "$(tgit -C "$repo" rev-parse refs/tags/v9.9.9)" = "$head"
reset

echo "== bin/release.sh, what it runs"
# Its code without the quoted text (the messages); a "$(…)" stays, it runs.
code_=$(sed -E 's/"([^"$]|\$[^("])*"//g' "$root/bin/release.sh")
check "nothing pushed, no tag made, no release file replaced or deleted" \
  test "$(grep -cE -e 'git push' -e 'git tag' -e 'gh release (upload|delete)' -e '--clobber' <<< "$code_")" -eq 0
check "it starts as a draft on the checked commit" grep -qE '^gh release create .* --draft --target  ' <<< "$code_"
check "one gh release edit, which publishes the draft" \
  test "$(grep -E 'gh release edit' <<< "$code_" | grep -cE 'gh release edit +-R +--draft=false( |$)')/$(grep -cE 'gh release edit' <<< "$code_")" = 1/1
# first <regex>: the number of the first line of the script's code that matches.
first() { grep -nE "$1" <<< "$code_" | head -n 1 | cut -d: -f1; }
check "one question" test "$(grep -c 'read -r -p' <<< "$code_")" = 1
check "it asks before it builds" test "$(first '^read -r -p')" -lt "$(first '^RECIPES_COMMIT=.* bin/build-release.sh')"
check "it builds before it signs" test "$(first '^RECIPES_COMMIT=.* bin/build-release.sh')" -lt "$(first 'minisign -S')"

[ "$failed" -eq 0 ] || { echo "$failed failed"; exit 1; }
echo "All passed."
