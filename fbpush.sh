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


# check if token is valid
# hub api user would be better

set +e
hub issue labels >> /dev/null

if [ $? -eq 1 ]; then
    echo "Wrong hub authentification token!"
    exit 1
fi

set -e


MSG="$(git log -1 --pretty=%B)"


function sanityCheck(){
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
  echo "✔ fast forward ok"
}


sanityCheck

# find out number of branches
# look only for remotes
echo "Checking for existing fbpush"

set +e
NUM_BRANCHES="$(git branch -a | grep origin/fbpush -c)" || :
OLD_BRANCHNAME="$(git branch -a | grep origin/fbpush | awk -F "/" '{print $NF}' | head -1)"
set -e

JOIN_BRANCH=false

if [ $NUM_BRANCHES -gt 1 ]; then
    notify-send -u critical -a "fbpush" "Failed" ${PWD##*/}
    echo "Too many existing fbpush branches. (╯°□°）╯︵ ┻━┻" 1>&2
    exit 1
elif [ $NUM_BRANCHES -gt 0 ]; then
    # read input
    while true; do
        git branch -a | grep origin/fbpush
        read -p "Existing fbpush branch. If the branch list contains one of your own branches, you should not join! This will rebase your branch onto the other person's branch. Please be sure you want to do this. Wanna join? (y/n)" yn
        case $yn in
            [Yy]* )
              JOIN_BRANCH=true
            break;;
            [Nn]* ) exit;;
            * ) echo "Please answer yes or no.";;
        esac
    done
else
    echo "✔ no existing fbpush branches found, looks like you're good to go!"
fi


CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$@" = "attach" ]] && [[ "$CURRENT_BRANCH" != "master" ]] && [[ $JOIN_BRANCH == "false" ]]; then  # no fbpush branch
    BRANCH_NAME="$CURRENT_BRANCH"
elif [[ $JOIN_BRANCH = "true" ]]; then        # push on existing fbpush
    echo "Join fbpush branches"
    git checkout -b $BRANCH_NAME
    git remote update
    git rebase origin/$OLD_BRANCHNAME
    git push origin $BRANCH_NAME:$BRANCH_NAME
else        # create new fbpush branch
    git checkout -b $BRANCH_NAME
fi


function cleanup() {
    echo "cleaning up $BRANCH_NAME"
    git branch -d $BRANCH_NAME
}
trap cleanup EXIT

function bailoutArmageddon() {
    echo "Nuking everything, as per your command"
    git push origin :$BRANCH_NAME
    notify-send -u critical -a "fbpush" "AMAR-GEDDON" ${PWD##*/}
    exit 1
}

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

function hotReplace() {
    sanityCheck
    git branch -D $BRANCH_NAME
    git checkout -b $BRANCH_NAME
    git push --force origin $BRANCH_NAME:$BRANCH_NAME
    git checkout master
    LAST_STATUS="no status"
}

function openCIJob() {
    hub ci-status $BRANCH_NAME -v | awk '{ print $NF }' | xargs xdg-open || :
}

PROJECT=$(basename "$PWD")
PRISTINE_TITLE="$PROJECT - Waiting for next CI check on $BRANCH_NAME."
LAST_STATUS=""

echo "Pushing branch to remote to trigger CI"
git push origin $BRANCH_NAME:$BRANCH_NAME

echo "Back to master"
git checkout master

while true; do
    if [ -t 1 ] ; then # true if fd 1 is open and points to a term
        set +e
        goat --time=30 --title="$PRISTINE_TITLE. $LAST_STATUS" -m "64:a:AMAR-GEDDON - destroy local and remote branch and quit" -m "65:r:Hot replace - forcepush current head into the fbpush branch and wait for that instead" -m "66:j:Job - ★ NEW ★ Browse CI job"
        RETCODE=$?
        set -e
        if [ $RETCODE -eq 1 ]; then
            CI_STATUS="<canceled by you>"
            bailout
        fi
        if [ $RETCODE -eq 64 ]; then
            bailoutArmageddon
        fi
        if [ $RETCODE -eq 65 ]; then
            hotReplace
        fi
        if [ $RETCODE -eq 66 ]; then
            openCIJob
        fi
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
if [[ $JOIN_BRANCH = "true" ]]; then
  git reset --hard origin/master
else
  git merge --ff-only origin/master
fi
notify-send -u normal -a "fbpush" "Done" ${PWD##*/}
