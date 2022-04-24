#!/bin/sh
set -eu

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "${BRANCH}" != 'devel' ]; then
  echo "error: deploy script only works from the 'devel' branch"
  exit 1
else
  MSG="${1:?"missing commit message"}"
  git add .
  git commit -m "${MSG}"
  git push
  git checkout master
  git merge devel
  git push
  get checkout devel
  echo "finished deploying"
fi
