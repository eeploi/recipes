#!/usr/bin/env bash
# Prints every path in /etc with its type, mode, owner and link target, and every file's content,
# so two runs can be compared. For CI only.
set -euo pipefail
find /etc -xdev -printf '%p %y %m %u:%g %l\n' | LC_ALL=C sort
find /etc -xdev -type f -exec sha256sum {} + | LC_ALL=C sort -k2
