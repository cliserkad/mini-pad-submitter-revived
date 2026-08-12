#!/usr/bin/env bash
# Rewrite the committer identity on a range of commits to cliserkad <0_0@cliserkad.xyz>,
# preserving each commit's author (name/email/date) and its original committer date.
#
# Dry run by default. Nothing is rewritten until you pass --apply.
#
#   scripts/recommit-committer.sh                        # show what would change (master..HEAD)
#   scripts/recommit-committer.sh --apply                # rewrite the replayed entries
#   scripts/recommit-committer.sh --range HEAD --apply   # rewrite every commit on the branch
#
set -euo pipefail

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
TARGET_NAME="cliserkad"
TARGET_EMAIL="0_0@cliserkad.xyz"   # matches the current global user.email
RANGE="master..HEAD"               # the replayed entries; use "HEAD" for the whole branch
APPLY=0
SIGN="auto"                        # auto | yes | no

while [ $# -gt 0 ]; do
    case "$1" in
        --apply)    APPLY=1 ;;
        --range)    RANGE="$2"; shift ;;
        --email)    TARGET_EMAIL="$2"; shift ;;
        --name)     TARGET_NAME="$2"; shift ;;
        --sign)     SIGN="yes" ;;
        --no-sign)  SIGN="no" ;;
        -h|--help)  sed -n '2,12p' "$0"; exit 0 ;;
        *)          echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

cd "$REPO"

[ -z "$(git status --porcelain --untracked-files=no)" ] || {
    echo "working tree has staged/unstaged changes; commit or stash first" >&2
    exit 1
}

# Re-signing: filter-branch rebuilds commits with git commit-tree, which drops the
# existing gpgsig header. Re-sign when the repo signs by default, so rewritten history
# is not silently downgraded to unsigned.
if [ "$SIGN" = "auto" ]; then
    if [ "$(git config --get commit.gpgsign || echo false)" = "true" ]; then SIGN=yes; else SIGN=no; fi
fi

mapfile -t COMMITS < <(git rev-list --reverse "$RANGE")
[ "${#COMMITS[@]}" -gt 0 ] || { echo "no commits in range $RANGE"; exit 0; }

changing=0
for c in "${COMMITS[@]}"; do
    ce=$(git show -s --format='%ce' "$c")
    if [ "$ce" != "$TARGET_EMAIL" ]; then
        changing=$((changing + 1))
        printf '  %s  %-45s -> %s\n' "$(git show -s --format='%h' "$c")" "$ce" "$TARGET_EMAIL"
    fi
done

echo
echo "range          : $RANGE"
echo "commits        : ${#COMMITS[@]}"
echo "committer fixes: $changing"
echo "re-sign        : $SIGN"

if [ "$APPLY" -ne 1 ]; then
    echo
    echo "dry run — re-run with --apply to rewrite (every commit in the range gets a new SHA)"
    exit 0
fi

BACKUP="refs/backup/pre-recommit-$(date +%Y%m%d-%H%M%S)"
git update-ref "$BACKUP" HEAD
echo "backup ref: $BACKUP -> $(git rev-parse --short HEAD)"

if [ "$SIGN" = "yes" ]; then
    COMMIT_FILTER='git commit-tree -S "$@"'
else
    COMMIT_FILTER='git commit-tree "$@"'
fi

# --env-filter runs per commit; GIT_AUTHOR_* and GIT_COMMITTER_DATE are left untouched,
# so authorship and the original commit timestamps survive the rewrite.
FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch --force \
    --env-filter "
        export GIT_COMMITTER_NAME='$TARGET_NAME'
        export GIT_COMMITTER_EMAIL='$TARGET_EMAIL'
    " \
    --commit-filter "$COMMIT_FILTER" \
    -- "$RANGE"

echo
echo "done. verify with:"
echo "  git log --format='%h %ae | %ce | %ad | %s' --date=short $RANGE | head"
echo "  git log --show-signature -1"
echo "  git diff $BACKUP HEAD          # must be empty: trees unchanged"
echo "to undo: git reset --hard $BACKUP"
