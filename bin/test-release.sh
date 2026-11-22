#!/usr/bin/env bash
# Tests bin/release.sh against a fake GitHub, so no real release, tag or draft is made: a copy of
# the working tree in a repo of its own with a local origin, a gh stub, and minisign with a test key
# without a password. The stub keeps the release in $GH_STATE/release ("<draft> <commit>", true for
# a draft) and its files in $GH_STATE/assets; publishing makes the tag in the origin, lightweight,
# as GitHub does. GH_FAIL: create (the draft is made, its files don't upload), extra (a file more),
# corrupt or badsig (what a download gives), tagrace (a tag made on GitHub during the download),
# publish (the draft stays), noview (publish, and GitHub can't be asked after), late (published,
# then an error), swap (a file changed while it was a draft, seen once published). GH_IMMUTABLE=false:
# the published release is not immutable. GH_CI: what CI on the commit gives.
# Also bin/build-release.sh with RECIPES_COMMIT: the same bytes as from a tag on that commit.
# Needs git, minisign, script and timeout. Runs without GitHub: CI runs it, and so can you.
set -euo pipefail
export LC_ALL=C
root=$(cd "$(dirname "$0")/.." && pwd)
for cmd in git minisign script timeout; do
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
  "api repos/eeploi/helper/releases/tags/"*) exit 0 ;;
  "api repos/eeploi/recipes/releases?per_page=100")
    [ -f "$s/release" ] || exit 0
    read -r draft _ < "$s/release"
    if [ "$draft" = true ]; then echo draft; else echo published; fi ;;
  "api repos/eeploi/recipes/immutable-releases") echo true ;;
  "run list") echo "${GH_CI:-completed success}" ;;
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
    while [ $# -gt 0 ]; do [ "$1" != -D ] || dir=$2; shift; done
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
# git without the user's own config (signing, hooks), and never on the real repo (GIT_DIR from a hook, say).
env_=(-u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u RECIPES_COMMIT -u RECIPES_DIR -u RECIPES_PUB
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GH_STATE="$t/gh" GH_ORIGIN="$t/origin.git" GH_TAG=v9.9.9
  PATH="$t/stubs:$PATH" RECIPES_KEY="$t/key.key")
tgit() { env "${env_[@]}" git -c user.name=Test -c user.email=test@example.com "$@"; }

# The tracked files as they are now, with the test key as minisign.pub.
git -C "$root" ls-files -z | (cd "$root" && tar --null -T - -cf -) | tar -xf - -C "$repo"
cp "$t/key.pub" "$repo/minisign.pub"
tgit init -q --bare "$t/origin.git"
tgit -C "$repo" init -q -b main
tgit -C "$repo" add -A
tgit -C "$repo" commit -qm one
tgit -C "$repo" remote add origin "$t/origin.git"
tgit -C "$repo" push -q origin main
head=$(tgit -C "$repo" rev-parse HEAD)
short=${head:0:7}
undo="check it with gh release view v9.9.9 -R eeploi/recipes, delete it with gh release delete v9.9.9 -R eeploi/recipes, then run this again"
args=(9.9.9 1.1.0 example)

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
  out=$(cd "$repo" && env "${env_[@]}" bash bin/release.sh --check "${args[@]}" 2>&1) || code=$?
  expect "$@"
}
# run <answer> <exit code> <name> <expected output>: bin/release.sh in a terminal (script, util-linux
# or BSD), the answer typed at its question. The input stays open until it ends: at the end of its
# input, BSD script types an end of file before the answer.
run() {
  local answer=$1 cmd
  shift
  rm -f "$t/ended"
  cmd="bash bin/release.sh ${args[*]}"
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
  GH_FAIL=$1 run y 1 "$2" "release: $3: nothing was published and v9.9.9 was not made. A draft release v9.9.9 may be left on GitHub: $undo"
  draft "$2"
}

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
checks 0 "a new version passes the checks" "Checks passed. Nothing built or published (--check)."
expect 0 "the header shows a new release" "  release  new, titled eeploi-recipes 9.9.9"
check "the checks made nothing" test -z "$(grep -E '^release (create|edit)' "$t/gh/log")"
echo "true $head" > "$t/gh/release"
checks 1 "a draft of this version stops the checks, with how to delete it" \
  "release: eeploi/recipes has a draft release v9.9.9, left by a run that stopped: $undo"
expect 1 "the header shows the draft" "  release  a DRAFT exists, titled eeploi-recipes 9.9.9"
echo "false $head" > "$t/gh/release"
checks 1 "a release of this version stops the checks" \
  "release: eeploi/recipes already has a release v9.9.9: releases are immutable, release a new version"
expect 1 "the header shows the release" "  release  EXISTS, titled eeploi-recipes 9.9.9"
reset
tgit --git-dir="$t/origin.git" update-ref refs/tags/v9.9.9 "$head"
tgit -C "$repo" fetch -q origin 'refs/tags/*:refs/tags/*'
checks 1 "the tag of this version stops the checks" "release: v9.9.9 already exists: releases are immutable, release a new version"
reset
tgit --git-dir="$t/origin.git" update-ref refs/tags/v9.9.9 "$head"
checks 1 "the tag on GitHub only stops the checks" "the v* tags here are not GitHub's"
reset
GH_CI="completed failure" checks 1 "CI not green on main stops the checks" "release: CI on main at $short is not green (completed failure)"

echo "== bin/release.sh"
run n 1 "no at the question" "release: not published"
check "no at the question: no draft" test -z "$(grep -E '^release (create|edit)' "$t/gh/log")"
reset
left create "the draft's files don't upload" "could not create the draft"
checks 1 "the draft left by a failed run stops the next one" "release: eeploi/recipes has a draft release v9.9.9, left by a run that stopped"
reset
m=recipes-9.9.9-example-ubuntu-26.04.manifest
left extra "a file more in the draft" "the draft is not a draft on $short titled eeploi-recipes 9.9.9 with only the files built and signed (true $head notes.txt,$m,$m.minisig,recipes-9.9.9.tar.gz eeploi-recipes 9.9.9)"
reset
left corrupt "the draft's package is not the one built" "the draft's files are not the ones built and signed"
reset
left badsig "the draft's signature is not the one made" "the draft's files are not the ones built and signed"
reset
name="a tag made on GitHub since the checks"
GH_FAIL=tagrace run y 1 "$name" "release: v9.9.9 was made on GitHub since the checks, so this version can't be released: the draft was not published; delete it with gh release delete v9.9.9 -R eeploi/recipes and release a new version"
check "$name: still a draft" grep -q '^true ' "$t/gh/release"
check "$name: no run again" test -z "$(grep -F 'run this again' <<< "$out")"
reset
left publish "publishing fails" "could not publish the draft"
reset
name="publishing fails, and GitHub can't be asked after"
GH_FAIL=noview run y 1 "$name" "release: publishing v9.9.9 gave an error, and GitHub could not say whether it is published (HTTP 502: Bad Gateway): check gh release view v9.9.9 -R eeploi/recipes. Still a draft: $undo. Published: the version is released"
draft "$name"
reset
GH_FAIL=late run y 1 "an error after GitHub published it" \
  "release: publishing v9.9.9 gave an error, but GitHub shows it published: check gh release view v9.9.9 -R eeploi/recipes before anything else"
reset
GH_IMMUTABLE=false run y 1 "a release that is not immutable" \
  "release: v9.9.9 is published, but not as an immutable release titled eeploi-recipes 9.9.9 with only the files built and signed"
reset
GH_FAIL=swap run y 1 "a file changed before publishing, seen in the published release" \
  "release: the published files are not the ones built and signed"
reset

name="a new version"
run y 0 "$name" "Done: eeploi/recipes, v9.9.9 = $short, titled \"eeploi-recipes 9.9.9\"."
check "$name: the draft on the checked commit" grep -qE "^release create v9.9.9 .* -R eeploi/recipes --draft --target $head --title eeploi-recipes 9.9.9 --notes " "$t/gh/log"
check "$name: published after its files were checked" \
  test "$(sed -nE 's/^release (create|download|edit) .*/\1/p' "$t/gh/log" | paste -sd ' ' -)" = "create download edit download"
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

[ "$failed" -eq 0 ] || { echo "$failed failed"; exit 1; }
echo "All passed."
