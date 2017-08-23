#!/bin/bash
set -e -u -o pipefail

BRANCH_NAME="fbpush-$(whoami)-$(date +%Y%m%d%H%M%S)"

declare -a progress=("|" "/" "-" "\\")

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

echo "Pushing branch to remote to trigger CI"
git push origin $BRANCH_NAME:$BRANCH_NAME

echo "Back to master"
git checkout master

while true; do
    for i in $(seq 30); do
        for char in "${progress[@]}"; do
          echo -en "\e[0K\r$char Waiting for CI (next try in $(expr 30 - $i) seconds)";
          sleep .25;
        done
    done
    CI_STATUS="$(hub ci-status || :)"
    # need the extra trailing space in the string to overwrite the previous line :P
    echo -e "\e[0K\rCI status at $(date +%H:%M:%S): $CI_STATUS                                                 "
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

    echo "ERROR: do not know how to deal with $CI_STATUS"
    echo "Opening a PR for you to fix. Please close or fix the PR and delete the branch yourself"
    git checkout $BRANCH_NAME
    URL=$(hub pull-request -m "$MSG" | tr -d "\n")
    echo "Pull request at $URL"
    xdg-open "$URL"
    git checkout master
    exit 1
done

git push origin $BRANCH_NAME:master
git push origin :$BRANCH_NAME

git remote update
git merge --ff-only origin/master
