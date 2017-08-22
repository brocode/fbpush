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
    for i in $(seq 30); do echo -en "\e[0K\rRetrying in $(expr 30 - $i)..."; sleep 1; done
    CI_STATUS="$(hub ci-status || :)"
    echo "CI status: $CI_STATUS"
    [[ "$CI_STATUS" == "success" ]] && {
        echo "Ok to merge"
        break
    }

    [[ "$CI_STATUS" == "pending" ]] && {
        continue
    }

    [[ "$CI_STATUS" == "no status" ]] && {
        echo "No status yet - looks like your CI server is overloaded."
        continue
    }

    echo "ERROR: don\'t know how to deal with $CI_STATUS"
    echo "Please close the PR and delete the branch yourself"
    echo "     See https://github.com/github/hub/issues/1483 for context - this can\'t be automated with hub yet."
    xdg-open "$URL"
    exit 1
done

xdg-open "$URL"
echo "I have opened the pull request page. Please click on merge there and delete the remote branch."
echo "     See https://github.com/github/hub/issues/1483 for context - this can\'t be automated with hub yet."

git remote update
