#!/bin/sh
set -eu

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "${BRANCH}" != 'devel' ]; then
  echo "error: deploy script only works from the 'devel' branch"
  exit 1
else
  MSG="${1:?"missing commit message"}"
  echo "staging updated files to devel branch ..."
  git add .
  echo "committing updates into devel branch..."
  git commit -m "${MSG}"
  echo "pushing devel branch ..."
  git push
  echo "checking out master branch ..."
  git checkout master
  echo "merging devel branch into master branch ..."
  git merge devel
  echo "pushing master branch ..."
  git push
  echo "checking out devel branch ..."
  git checkout devel
  echo "finished deploying"
fi
