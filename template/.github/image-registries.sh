#!/usr/bin/env bash
# The repositories a release's image goes to, one a line, each logged in before anything is
# pushed: GHCR's always (the job's token), Docker Hub's when both vars.DOCKERHUB_USERNAME and
# secrets.DOCKERHUB_TOKEN are set -- the name vars.DOCKERHUB_REPOSITORY, else <username>/<the
# GitHub repository's name>. image.yml's; it passes GH_TOKEN and DOCKERHUB_USERNAME,
# DOCKERHUB_TOKEN and DOCKERHUB_REPOSITORY (empty when unset).
set -euo pipefail

docker login ghcr.io --username "$GITHUB_ACTOR" --password-stdin <<< "${GH_TOKEN:?}" >&2
echo "ghcr.io/${GITHUB_REPOSITORY,,}"

username=${DOCKERHUB_USERNAME:-}
token=${DOCKERHUB_TOKEN:-}
if [[ -z $username && -z $token ]]; then
  exit 0
elif [[ -z $username || -z $token ]]; then
  echo "error: Docker Hub needs both vars.DOCKERHUB_USERNAME and secrets.DOCKERHUB_TOKEN" >&2
  exit 1
fi
repository=${DOCKERHUB_REPOSITORY:-$username/${GITHUB_REPOSITORY#*/}}
repository=${repository,,}
# a reference Docker takes (its grammar's path components), its name as Docker Hub's: lowercase
# letters and digits, `-` and `_` between them, 2 to 255 characters (Docker Hub's docs)
name=${repository#*/}
if [[ ! $repository =~ ^[a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*/[a-z0-9]+((_|__|-+)[a-z0-9]+)*$ ]] \
  || (( ${#name} < 2 || ${#name} > 255 )); then
  echo "error: '$repository' is no Docker Hub repository: set vars.DOCKERHUB_REPOSITORY" >&2
  exit 1
fi
docker login docker.io --username "$username" --password-stdin <<< "$token" >&2
echo "docker.io/$repository"
