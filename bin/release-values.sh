# shellcheck shell=bash
# Sourced by bin/release.sh and by CI.
# D-26: the values a release takes from the commit it releases, read with strict patterns. Each function reads one file and prints its value on stdout,
# or prints why it can't and returns 1. README, Releases, has the rules.

provider_name='^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$' # the helper's rule, as bin/build-release.sh

# changelog_version <file>: the version of its top version heading. The first heading is
# "## Unreleased", with nothing under it but empty lines; the next is "## VERSION", that version.
# Each part a number without a leading zero. With "open", lines under "## Unreleased" are allowed:
# the layout CI checks on a pull request.
changelog_version() {
  awk -v open="${2:-}" '
    function stop(why) { print why; code = 1; exit }
    /^## / {
      n++
      if (n == 1) { if ($0 != "## Unreleased") stop("the first heading is not ## Unreleased"); next }
      v = substr($0, 4)
      if (v !~ /^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$/) stop("the heading after ## Unreleased is not ## VERSION, such as ## 0.6.0")
      print v; found = 1; exit
    }
    n == 1 && NF && open != "open" { stop("## Unreleased is not empty: move its lines under a version") }
    END {
      if (code) exit code
      if (!n) { print "no ## Unreleased heading"; exit 1 }
      if (!found) { print "no ## VERSION heading after ## Unreleased"; exit 1 }
    }
  ' "$1"
}

# helper_tag <file>: the version of the one HELPER_TAG line in CI's workflow, without its v.
helper_tag() {
  local lines
  lines=$(grep -E '^ *HELPER_TAG:' "$1" || true)
  [ "$(grep -c . <<< "$lines")" = 1 ] || { echo "not one HELPER_TAG line"; return 1; }
  [[ $lines =~ ^\ +HELPER_TAG:\ v((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))$ ]] || { echo "HELPER_TAG is not vN.N.N: $lines"; return 1; }
  echo "${BASH_REMATCH[1]}"
}

# helper_pubkey <file>: the one HELPER_PUBKEY line in CI's workflow, the helper's release key CI
# checks HELPER_TAG with: a minisign public key, RW and 54 more base64 characters.
helper_pubkey() {
  local lines
  lines=$(grep -E '^ *HELPER_PUBKEY:' "$1" || true)
  [ "$(grep -c . <<< "$lines")" = 1 ] || { echo "not one HELPER_PUBKEY line"; return 1; }
  [[ $lines =~ ^\ +HELPER_PUBKEY:\ (RW[A-Za-z0-9+/]{54})$ ]] || { echo "HELPER_PUBKEY is not a minisign public key: $lines"; return 1; }
  echo "${BASH_REMATCH[1]}"
}

# providers_list <file>: its provider names, one per line. "#" lines and empty ones are skipped;
# at least one, none twice.
providers_list() {
  local line names=() dup
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in '' | '#'*) continue ;; esac
    [[ $line =~ $provider_name ]] || { echo "$line is no provider name: a-z, 0-9 and inner -, at most 32"; return 1; }
    names+=("$line")
  done < "$1"
  [ "${#names[@]}" -gt 0 ] || { echo "no provider"; return 1; }
  dup=$(printf '%s\n' "${names[@]}" | sort | uniq -d | head -n 1)
  [ -z "$dup" ] || { echo "$dup is there twice"; return 1; }
  printf '%s\n' "${names[@]}"
}
