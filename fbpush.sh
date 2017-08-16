#!/bin/bash
set -e -u -o pipefail

BRANCH_NAME=${1:? "no branch name specified, usage: $0 <branch> <msg>"}
MSG=${2:? "no message specified, usage: $0 <branch> <msg>"}

git commit -m "$MSG"
git co -b $BRANCH_NAME
git push origin $BRANCH_NAME:$BRANCH_NAME

URL=$(hub pull-request -m "$MSG" | tr -d "\n")

echo "Pull request at $URL"

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

    echo "ERROR: don't know how to deal with $CI_STATUS"
    exit 1
done

xdg-open "$URL"
echo "I have opened the pull request page. Please click on merge there and delete the remote branch."
echo "     See https://github.com/github/hub/issues/1483 for context - this can't be automated with hub yet."

git co master
git branch -d $BRANCH_NAME
