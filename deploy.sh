#!/bin/sh
set -eu

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "${BRANCH}" != 'devel' ]; then
  echo "error: deploy script only works from the 'devel' branch"
  exit 1
else
  echo "staging updated files to devel branch ..."
  git add .
  echo "committing updates into devel branch..."
  git commit "$@"
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
  source <(grep "^readonly VERSION=" ./zfsync)
  if [ -z "${VERSION:-}" ]; then
    echo "failed to update version"
  else
    # from https://stackoverflow.com/a/61921674
    NEXTVERSION=$(echo ${VERSION} | awk -F. -v OFS=. '{$NF += 1 ; print}')
    echo "bumping version number from $VERSION to $NEXTVERSION ..."
    sed -i "s/^readonly VERSION=\"$VERSION\"/readonly VERSION=\"$NEXTVERSION\"/" ./zfsync
  fi
fi
