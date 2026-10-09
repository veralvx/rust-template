#!/usr/bin/env bash
# The repositories a release's image goes to, one a line, each logged in before anything is
# pushed: GHCR's always (the job's token), Docker Hub's when both its secrets are set -- the name
# vars.DOCKERHUB_REPOSITORY, else <username>/<repository>. image.yml's; it passes GH_TOKEN and
# DOCKERHUB_USERNAME, DOCKERHUB_TOKEN and DOCKERHUB_REPOSITORY (empty when unset).
set -euo pipefail

docker login ghcr.io --username "$GITHUB_ACTOR" --password-stdin <<< "${GH_TOKEN:?}" >&2
echo "ghcr.io/${GITHUB_REPOSITORY,,}"

username=${DOCKERHUB_USERNAME:-}
token=${DOCKERHUB_TOKEN:-}
if [[ -z $username && -z $token ]]; then
  exit 0
elif [[ -z $username || -z $token ]]; then
  echo "error: Docker Hub needs both secrets, DOCKERHUB_USERNAME and DOCKERHUB_TOKEN" >&2
  exit 1
fi
repository=${DOCKERHUB_REPOSITORY:-$username/${GITHUB_REPOSITORY#*/}}
repository=${repository,,}
# Docker Hub's names: lowercase letters, digits, `-` and `_`, 2 to 255 of them (its docs)
if [[ ! $repository =~ ^[^/]+/[a-z0-9_-]{2,255}$ ]]; then
  echo "error: '$repository' is no Docker Hub repository: set vars.DOCKERHUB_REPOSITORY" >&2
  exit 1
fi
docker login docker.io --username "$username" --password-stdin <<< "$token" >&2
echo "docker.io/$repository"
