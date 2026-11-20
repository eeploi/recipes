#!/usr/bin/env bash
# Builds a release from its tag, not from the working copy: the package (the files a server runs,
# as a tar.gz) and a manifest per provider and Ubuntu release, in dist/VERSION/. Signs nothing: it
# prints the manifests to sign with the recipes key (RECIPES_KEY sets another key file).
# Usage: bin/release.sh VERSION MIN_HELPER PROVIDER...   such as bin/release.sh 0.4.0 0.5.0 example
set -euo pipefail
export LC_ALL=C # the name rules below match ASCII only, as the helper's
cd "$(dirname "$0")/.."
key=${RECIPES_KEY:-$HOME/.minisign/eeploi-recipes.key}

[ "$#" -ge 3 ] || { echo "Usage: bin/release.sh VERSION MIN_HELPER PROVIDER..." >&2; exit 2; }
version=$1
min_helper=$2
shift 2
semver='^[0-9]+\.[0-9]+\.[0-9]+$'
[[ "$version" =~ $semver ]] || { echo "$version is no version, such as 0.4.0" >&2; exit 2; }
[[ "$min_helper" =~ $semver ]] || { echo "$min_helper is no helper version, such as 0.5.0" >&2; exit 2; }
provider_name='^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$'   # the helper's rule (recipe-run)
part='[A-Za-z0-9_][A-Za-z0-9._-]*'
path_name="^$part(/$part)*\$"   # the helper's rule for a path in a manifest (recipe-run)
for provider; do
  [[ "$provider" =~ $provider_name ]] || { echo "$provider is no provider name: a-z, 0-9 and inner -, at most 32" >&2; exit 2; }
done
tag=v$version
git rev-parse -q --verify "refs/tags/$tag" >/dev/null || { echo "$tag is no tag" >&2; exit 1; }
out=dist/$version
[ ! -e "$out" ] || { echo "$out exists" >&2; exit 1; }

# Built in $tmp/out and moved to $out at the end, so a run that fails leaves nothing half built.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
build=$tmp/out
mkdir "$build" "$tmp/tree"
git archive "$tag" | tar -x -C "$tmp/tree"
# The manifest takes its file names and values from these. bash drops a NUL when it reads a line,
# here and in the helper, so a NUL in them would change a name or value unseen. Then every path
# the manifest will hold, before bin/check-layout.sh reads them.
for file in "$tmp"/tree/ubuntu-*/steps "$tmp/tree/markers"; do
  [ -f "$file" ] || { echo "${file#"$tmp/tree/"} is not in $tag" >&2; exit 1; }
  # shellcheck disable=SC2094 # both only read it
  tr -d '\000' < "$file" | cmp -s - "$file" || { echo "${file#"$tmp/tree/"} in $tag holds a NUL" >&2; exit 1; }
done
path_ok() { [[ "$1" =~ $path_name ]] || { echo "$1 is no path the helper takes: each part $part" >&2; exit 1; }; }
for list in "$tmp"/tree/ubuntu-*/steps; do
  path_ok "$(basename "$(dirname "$list")")/php-source.sh"
  while IFS= read -r file || [ -n "$file" ]; do
    case "$file" in '' | '#'*) continue ;; esac
    path_ok "$file"
  done < "$list"
done
"$tmp/tree/bin/check-layout.sh" >/dev/null || { echo "$tag fails bin/check-layout.sh" >&2; exit 1; }

# The release tags up to this one, in version order.
tags=()
while IFS= read -r t; do
  [[ "$t" =~ ^v${semver#^} ]] || continue
  tags+=("$t")
  [ "$t" != "$tag" ] || break
done < <(git tag -l 'v*' --sort=v:refname)

# The release a file came in, and the first release since which it is the same as in this one.
versions() {
  local now t blob introduced='' changed=''
  now=$(git rev-parse "$tag:$1")
  for t in "${tags[@]}"; do
    blob=$(git rev-parse -q --verify "$t:$1") || blob=''
    if [ -n "$blob" ] && [ -z "$introduced" ]; then introduced=${t#v}; fi
    if [ "$blob" != "$now" ]; then changed=''; elif [ -z "$changed" ]; then changed=${t#v}; fi
  done
  echo "$introduced $changed"
}

sha() { sha256sum "$tmp/tree/$1" | cut -d' ' -f1; }

paths=()
for list in "$tmp"/tree/ubuntu-*/steps; do
  os=$(basename "$(dirname "$list")")
  # The steps in run order, then every other file a run reads.
  body=$tmp/$os.body
  files=()
  checks=()
  while IFS= read -r file || [ -n "$file" ]; do
    case "$file" in '' | '#'*) continue ;; esac
    name=${file##*/}
    case "$name" in
      [0-9][0-9]-*.sh)
        read -r marker flags < <(awk -v f="$file" '$1 !~ /^#/ && $2 == f { print $1, ($3 == "" ? "-" : $3) }' "$tmp/tree/markers") ||
          { echo "$file has no marker in markers" >&2; exit 1; }
        echo "step $(sha "$file") $marker $(versions "$file") $flags $file"
        [ ! -f "$tmp/tree/${file%.sh}.check.sh" ] || checks+=("${file%.sh}.check.sh")
        paths+=("$file")
        ;;
      *) files+=("$file") ;;
    esac
  done < "$list" > "$body"
  for file in "$os/php-source.sh" stack/fingerprint.sh; do
    [ -f "$tmp/tree/$file" ] || { echo "$file is not in $tag" >&2; exit 1; }
  done
  for file in "${files[@]}" "${checks[@]}" "$os/php-source.sh" stack/fingerprint.sh; do
    echo "file $(sha "$file") $file"
    paths+=("$file")
  done >> "$body"

  for provider; do
    {
      echo 'format 1'
      echo "release $version"
      echo "target $provider $os"
      echo "min-helper $min_helper"
      cat "$body"
    } > "$build/recipes-$version-$provider-$os.manifest"
  done
done

# One package for every manifest: each file once, in a fixed order, so the same tag builds the same bytes.
# Only plain files: the package would hold a link where the manifest has its target's SHA-256.
sorted=()
while IFS= read -r path; do sorted+=("$path"); done < <(printf '%s\n' "${paths[@]}" | LC_ALL=C sort -u)
listed=0
while read -r mode _ _ path; do
  case "$mode" in 100644 | 100755) ;; *) echo "$path in $tag is no plain file (mode $mode)" >&2; exit 1 ;; esac
  listed=$((listed + 1))
done < <(git --literal-pathspecs ls-tree -r "$tag" -- "${sorted[@]}")
[ "$listed" -eq "${#sorted[@]}" ] || { echo "git ls-tree lists $listed of ${#sorted[@]} files in $tag" >&2; exit 1; }
git archive --format=tar.gz -o "$build/recipes-$version.tar.gz" "$tag" "${sorted[@]}"

mkdir -p dist
mv "$build" "$out"
echo "Built $tag ($(git rev-parse "$tag^{commit}")) in $out:"
ls -1 "$out"
echo
echo 'Sign each manifest with the recipes key, then add the package, the manifests and their .minisig files to the GitHub release:'
for manifest in "$out"/*.manifest; do printf '  minisign -S -s %q -m %q\n' "$key" "$manifest"; done
