#!/bin/bash
## This GitHub Action for git commits any changed files and pushes 
## those changes back to the origin repository.
##
## Required environment variable:
## - $GITHUB_TOKEN: The token to use for authentication with GitHub 
## to commit and push changes back to the origin repository.
##
## Optional environment variables:
## - $WD_PATH: Working directory to CD into before checking for changes
## - $PUSH_BRANCH: Remote branch to push changes to
## - $BATCH_MAX_FILES: Maximum number of files to commit at one time

if [ "$DEBUG" == "false" ]
then
  # Carry on, but do quit on errors
  set -e
  echo DEBUG OFF
else
  # Verbose debugging
  # set -exuo pipefail
  echo DEBUG ON
  export LOG_LEVEL=debug
  export ACTIONS_STEP_DEBUG=true
fi

# If WD_PATH is defined, then cd to it
if [ ! -z "$WD_PATH" ]
then
  echo "Changing dir to $WD_PATH"
  cd "$WD_PATH"
fi

# Set up .netrc file with GitHub credentials
git_setup ( ) {
  # Git requires our "name" and email address -- use GitHub handle
  git config user.email "$GITHUB_ACTOR@users.noreply.github.com"
  git config user.name "$GITHUB_ACTOR"
}

BATCH_MAX_FILES=$((BATCH_MAX_FILES+0))

# Batch remove/add files up to a maximum limit
git_batch ( ) {
  commitpush() {
    git commit -m "$COMMIT_MESSAGE"
    git push
  }

  # remove deleted files
  removeFiles=()
  purgeRemoveFiles ( ) {
    git rm "${removeFiles[@]}"
    commitpush
    removeFiles=()
  }
  pushRemoveFile ( ) {
    removeFiles+=("$1")
    countRemoveFiles=${#removeFiles[@]}
    if [ "$countRemoveFiles" -ge "$BATCH_MAX_FILES" ]; then
      purgeRemoveFiles
    fi
  }
  IFS=""
  while read -r -d $'\0' line; do
    IFS="\0";
    set -- $line
    pushRemoveFile "${line:3}"
    IFS=""
  done < <(git status -u --porcelain -z | grep -z '^\( D\)')
  countRemoveFiles=${#removeFiles[@]}
  if [ "countRemoveFiles" -gt 0 ]; then
    purgeRemoveFiles
  fi

  # add missing files
  addFiles=()
  purgeAddFiles ( ) {
    git add "${addFiles[@]}"
    commitpush
    addFiles=()
  }
  pushAddFile ( ) {
    addFiles+=("$1")
    countAddFiles=${#addFiles[@]}
    if [ "$countAddFiles" -ge "$BATCH_MAX_FILES" ]; then
      purgeAddFiles
    fi
  }
  IFS=""
  while read -r -d $'\0' line; do
    IFS="\0";
    set -- $line
    pushAddFile "${line:3}"
    IFS=""
  done < <(git status -u --porcelain -z)
  countAddFiles=${#addFiles[@]}
  if [ "$countAddFiles" -gt 0 ]; then
    purgeAddFiles
  fi
}

# This section only runs if there have been file changes
echo "Checking for uncommitted changes in the git working tree."
if expr $(git status --porcelain | wc -l) \> 0 >/dev/null
then 
  git_setup
  if expr "$BATCH_MAX_FILES" \> 0 >/dev/null
  then
    git_batch
  else
    git add .
    git commit -m "$COMMIT_MESSAGE"
    git push
  fi
else 
  echo "Working tree clean. Nothing to commit."
fi
