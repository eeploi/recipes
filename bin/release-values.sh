# shellcheck shell=bash
# Sourced by bin/release and by CI.
# D-26: the values a release takes from the commit it releases, read with strict patterns. Each function reads one file and prints its value on stdout,
# or prints why it can't and returns 1. README, Releases, has the rules.

provider_name='^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$' # the helper's rule, as bin/build-release.sh

# changelog_version <file>: the version of its top version heading. The first heading is
# "## Unreleased", with nothing under it but empty lines; the next is "## VERSION", that version,
# with lines under it. Each part a number without a leading zero. With "open", lines under
# "## Unreleased" are allowed: the layout CI checks on a pull request.
changelog_version() {
  awk -v open="${2:-}" '
    function stop(why) { print why; code = 1; exit }
    /^## / {
      n++
      if (n == 1) { if ($0 != "## Unreleased") stop("the first heading is not ## Unreleased"); next }
      if (n == 3) exit
      v = substr($0, 4)
      if (v !~ /^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$/) stop("the heading after ## Unreleased is not ## VERSION, such as ## 0.6.0")
      next
    }
    n == 1 && NF && open != "open" { stop("## Unreleased is not empty: move its lines under a version") }
    n == 2 && NF { notes++ }
    END {
      if (code) exit code
      if (!n) { print "no ## Unreleased heading"; exit 1 }
      if (n < 2) { print "no ## VERSION heading after ## Unreleased"; exit 1 }
      if (!notes) { print "nothing under ## " v; exit 1 }
      print v
    }
  ' "$1"
}

# ci_value <file> <NAME> <regex> <what>: the value of the one "  NAME: value" line in CI's workflow,
# matching the regex (its first group is the value), or why not.
ci_value() {
  local lines
  lines=$(grep -E "^ *$2:" "$1" || true)
  [ "$(grep -c . <<< "$lines")" = 1 ] || { echo "not one $2 line"; return 1; }
  [[ $lines =~ ^\ +$2:\ $3$ ]] || { echo "$2 is not $4: $lines"; return 1; }
  echo "${BASH_REMATCH[1]}"
}
# helper_tag <file>: the version of HELPER_TAG, without its v.
helper_tag() { ci_value "$1" HELPER_TAG 'v((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))' vN.N.N; }
# helper_pubkey <file>: HELPER_PUBKEY, the helper's release key CI checks HELPER_TAG with: RW and 54
# more base64 characters.
helper_pubkey() { ci_value "$1" HELPER_PUBKEY '(RW[A-Za-z0-9+/]{54})' 'a minisign public key'; }

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
