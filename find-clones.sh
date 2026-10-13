#!/usr/bin/env bash
# Find every local clone of a GitHub repo, whatever directory name it was
# cloned as. See README.md for how it works and what it matches.
#
# Usage: [TARGET_REPO=owner/name] find-clones.sh [root ...]

set -uo pipefail

TARGET_REPO="${TARGET_REPO:-kubernetes/kubernetes}"

# URLs get lowercased before comparing (see is_target_url), so lowercase the
# target too. Otherwise TARGET_REPO=Vercel/Next.js could never match.
TARGET_REPO=$(printf '%s' "$TARGET_REPO" | tr '[:upper:]' '[:lower:]')

# is_target_url URL
#
# Returns success (0) if URL points at github.com/$TARGET_REPO. The same repo
# can be written several ways (https, scp-style SSH, ssh://; see README.md),
# so we clean the URL up first, then compare against a pattern that allows
# for all of them.
is_target_url() {
  local url

  # GitHub ignores case in owner and repo names. tr rather than ${var,,}
  # because macOS ships bash 3.2, which doesn't support it.
  url=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')

  # Strip a trailing slash, then a trailing ".git". Order matters: a URL
  # like ".../kubernetes.git/" needs the slash gone before ".git"
  # is the last thing on the line.
  url=${url%/}
  url=${url%.git}

  # [:/]+ covers ":" for scp-style SSH and "/" for https and ssh://. No "^"
  # anchor, so any scheme or "user@" can come before the host. The "$" anchor
  # stops "kubernetes-extras" from matching.
  #
  # $TARGET_REPO is quoted so it's matched as plain text. Without the quotes,
  # the dot in "vercel/next.js" would match any character, so "vercel/nextxjs"
  # would match too.
  [[ $url =~ github\.com[:/]+"$TARGET_REPO"$ ]]
}

# is_target_repo DIR
#
# Returns success (0) if any remote configured in the repo at DIR points at
# the target repo. Checking every remote (not just "origin") means a personal
# fork with the original repo set as "upstream" still counts. A broken repo
# produces no remotes and simply won't match.
is_target_repo() {
  local _key url
  while read -r _key url; do
    is_target_url "$url" && return 0
  done < <(git -C "$1" config --get-regexp '^remote\..*\.url$' 2>/dev/null)
  return 1
}

main() {
  local roots=("$@")
  [[ ${#roots[@]} -eq 0 ]] && roots=("$HOME")

  local found=0 git_path repo

  for root in "${roots[@]}"; do
    # .git can be a directory (normal clone) or a file (worktree, submodule),
    # and "find -name .git" matches both.
    while IFS= read -r -d '' git_path; do
      repo=$(dirname "$git_path")

      if is_target_repo "$repo"; then
        printf '%s\n' "$repo"
        found=1
      fi
    done < <(
      # Skip ~/Library, node_modules and .Trash entirely: they're slow to
      # search and never hold a clone we want. Don't descend into .git either,
      # but the rest of the working tree is still searched, so submodules are
      # found.
      find "$root" \
        \( -path "$HOME/Library" -o -name node_modules -o -name .Trash \) -prune \
        -o -name .git -print0 -prune 2>/dev/null
    )
  done

  [[ $found -eq 1 ]]
}

main "$@"
