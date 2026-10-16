#!/usr/bin/env bash
# A release's notes: CHANGELOG.md's first section, up to the second `## ` heading, refused unless
# it is the version's own (`just release` writes it on top). The release workflow's.
set -euo pipefail

changelog=${1:?usage: release-notes.sh CHANGELOG VERSION}
version=${2:?usage: release-notes.sh CHANGELOG VERSION}
notes=$(awk '/^## /{n++} n==1' "$changelog")
if [[ $notes != "## [$version]("* ]]; then
  echo "$changelog: the first section is not $version's" >&2
  exit 1
fi
printf '%s\n' "$notes"
