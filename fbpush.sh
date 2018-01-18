#!/bin/bash
set -e -u -o pipefail

BRANCH_NAME="fbpush-$(whoami)-$(date +%Y%m%d%H%M%S)"

command -v goat > /dev/null 2>&1 || {
    echo "goat not found in PATH. Please install from https://github.com/brocode/goat. For now you can download the binary here: https://github.com/brocode/goat/releases"
    exit 1
}


command -v hub >/dev/null 2>&1 || {
    echo "You need to install hub (https://github.com/github/hub) and it must be in your path."
    exit 1
}

MSG="$(git log -1 --pretty=%B)"

git remote update --prune

echo "Checking if your work applies as a fast forward for origin/master..."
MISSINGREFS=$(git rev-list --left-right HEAD...origin/master | grep '>') || :
[[ -z "$MISSINGREFS" ]] || {
    echo "There's remote work that you do not have locally. Please rebase onto origin/master first."
    for MISSING in $( echo $MISSINGREFS); do
        REF=$(echo $MISSING | tr -d '>')
        echo "  missing locally: $(git log --format=%B -n 1 $REF)"
    done
    exit 1
}
echo "✅ fast forward ok"

echo "Checking for existing fbpush"
if git branch -a | grep fbpush; then
    notify-send -u critical -a "fbpush" "Failed" ${PWD##*/}
    echo "Existing fbpush branches. (╯°□°）╯︵ ┻━┻" 1>&2
    exit 1
fi

echo "✅ no existing fbpush branches found, looks like you're good to go!"

git checkout -b $BRANCH_NAME

function cleanup() {
    echo "cleaning up $BRANCH_NAME"
    git branch -d $BRANCH_NAME
}
trap cleanup EXIT

function bailout() {
    echo "ERROR: do not know how to deal with $CI_STATUS"
    echo "Opening a PR for you to fix. Please close or fix the PR and delete the branch yourself"
    git checkout $BRANCH_NAME
    URL=$(hub pull-request -m "$MSG" | tr -d "\n")
    echo "Pull request at $URL"
    xdg-open "$URL"
    git checkout master
    echo "You can pwn the remote branch with this command:"
    echo "    git push origin :$BRANCH_NAME"
    notify-send -u critical -a "fbpush" "Failed" ${PWD##*/}
    exit 1
}

PRISTINE_TITLE="Waiting for next CI check on $BRANCH_NAME."
LAST_STATUS=""

echo "Pushing branch to remote to trigger CI"
git push origin $BRANCH_NAME:$BRANCH_NAME

echo "Back to master"
git checkout master

while true; do
    if [ -t 1 ] ; then # true if fd 1 is open and points to a term
        goat --time=30 --title="$PRISTINE_TITLE. $LAST_STATUS" || {
            CI_STATUS="<canceled by you>"
            bailout
        }
    else
        echo "$PRISTINE_TITLE. $LAST_STATUS"
        sleep 30 || bailout
    fi
    CI_STATUS="$(hub ci-status $BRANCH_NAME || :)"
    LAST_STATUS="Last checked at $(date +%H:%M:%S): $CI_STATUS"
    [[ "$CI_STATUS" == "success" ]] && {
        echo "Ok to merge"
        break
    }

    [[ "$CI_STATUS" == "pending" ]] && {
        continue
    }

    [[ "$CI_STATUS" == "no status" ]] && {
        LAST_STATUS="No status yet - looks like your CI server is overloaded."
        continue
    }

    bailout
done

git push origin $BRANCH_NAME:master || bailout
git push origin :$BRANCH_NAME || echo "Failed to delete remote spinoff branch $BRANCH_NAME, sorry"

git remote update
git merge --ff-only origin/master
notify-send -u normal -a "fbpush" "Done" ${PWD##*/}
