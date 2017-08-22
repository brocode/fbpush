#!/bin/bash
set -e -u -o pipefail

BRANCH_NAME="fbpush-$(whoami)-$(date +%Y%m%d%H%M%S)"

command -v hub >/dev/null 2>&1 || {
    echo "You need to install hub (https://github.com/github/hub) and it must be in your path."
    exit 1
}

MSG="$(git log -1 --pretty=%B)"

git checkout -b $BRANCH_NAME

function cleanup() {
  echo "cleaning up $BRANCH_NAME"
  git branch -d $BRANCH_NAME
}
trap cleanup EXIT

git push origin $BRANCH_NAME:$BRANCH_NAME

URL=$(hub pull-request -m "$MSG" | tr -d "\n")

echo "Pull request at $URL"

echo "Back to master"
git checkout master

while true; do
    sleep 30
    CI_STATUS="$(hub ci-status || :)"
    echo "CI status: $CI_STATUS"
    [[ "$CI_STATUS" == "success" ]] && {
        echo "Ok to merge"
        break
    }

    [[ "$CI_STATUS" == "pending" ]] && {
        echo "Will retry soon"
        continue
    }

    [[ "$CI_STATUS" == "no status" ]] && {
        echo "No status - looks like your CI server is overloaded. Will retry soon"
        continue
    }

    echo "ERROR: don't know how to deal with $CI_STATUS"
    exit 1
done

xdg-open "$URL"
echo "I have opened the pull request page. Please click on merge there and delete the remote branch."
echo "     See https://github.com/github/hub/issues/1483 for context - this can't be automated with hub yet."

git remote update
