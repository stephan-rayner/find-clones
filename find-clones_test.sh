#!/usr/bin/env bash
# Tests for find-clones.sh. Run: ./find-clones_test.sh
#
# Builds fake repos in a temp folder, runs the real script against it, and
# checks what it finds. Nothing outside the temp folder is touched, and the
# folder is deleted when the test finishes, pass or fail.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/find-clones.sh"

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

failures=0

# make_repo PATH REMOTE_NAME URL
#
# Creates an empty git repo at $ROOT/PATH with one remote pointing at URL.
# The repos have no files or commits: the main script only looks at .git and
# the remote URLs in the repo's config, so that's all we need to set up.
make_repo() {
  local dir="$ROOT/$1" remote_name="$2" url="$3"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add "$remote_name" "$url"
}

# assert_found PATH
#
# Passes if $ROOT/PATH appears as a full line in the script's output. The
# full-line match means "k8s" can't pass just because "k8s-worktree" was found.
assert_found() {
  if grep -qxF "$ROOT/$1" <<<"$output"; then
    echo "ok: found $1"
  else
    echo "FAIL: expected to find $1"
    failures=$((failures + 1))
  fi
}

# assert_not_found PATH
#
# Passes if $ROOT/PATH does not appear anywhere in the output. Deliberately
# not a full-line match: failing on any line that contains the path is
# stricter, and catches something inside node_modules/k8s turning up.
assert_not_found() {
  if grep -qF "$ROOT/$1" <<<"$output"; then
    echo "FAIL: did not expect to find $1"
    failures=$((failures + 1))
  else
    echo "ok: skipped $1"
  fi
}

# ---------------------------------------------------------------------------
# Set up repos the script SHOULD find. Each one covers a different way the
# same repo can be cloned or named.
# ---------------------------------------------------------------------------

# The plain, default clone.
make_repo "kubernetes" origin "https://github.com/kubernetes/kubernetes"
# Folder renamed, and the URL has the ".git" suffix.
make_repo "renamed-https-dotgit" origin "https://github.com/kubernetes/kubernetes.git"
# scp-style SSH: "git@host:owner/repo", note the colon instead of a slash.
make_repo "renamed-scp" origin "git@github.com:kubernetes/kubernetes.git"
# URL-style SSH: "ssh://git@host/owner/repo".
make_repo "renamed-ssh-url" origin "ssh://git@github.com/kubernetes/kubernetes.git"
# Trailing slash, which git accepts and people sometimes paste in.
make_repo "trailing-slash" origin "https://github.com/kubernetes/kubernetes/"
# Mixed case. GitHub ignores case in owner and repo names, so we should too.
make_repo "mixed-case" origin "https://GitHub.com/Kubernetes/KuberNetes.git"
# Username in the URL, common when using HTTPS with a token.
make_repo "with-userinfo" origin "https://someone@github.com/kubernetes/kubernetes.git"
# Buried several levels deep, under a hidden (dot) folder like ~/.config.
make_repo ".hidden/deeply/nested/k8s" origin "git@github.com:kubernetes/kubernetes.git"
# Spaces in the path, like "My Projects".
make_repo "path with spaces" origin "git@github.com:kubernetes/kubernetes.git"
# A personal fork as origin, with the original repo added as "upstream".
# Only the second remote matches, which proves we check every remote.
make_repo "fork-with-upstream" origin "git@github.com:someone/kubernetes.git"
git -C "$ROOT/fork-with-upstream" remote add upstream "https://github.com/kubernetes/kubernetes.git"

# A worktree, where .git is a file pointing back at the main repo instead of
# a folder. "git worktree add" refuses to run on a repo with no commits, so we
# make an empty one first, with a throwaway author so it works without any
# global git config.
git -C "$ROOT/kubernetes" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$ROOT/kubernetes" worktree add -q "$ROOT/k8s-worktree" 2>/dev/null

# ---------------------------------------------------------------------------
# Set up decoys the script should NOT find. Each one is close enough to the
# real thing that a sloppy match could pick it up.
# ---------------------------------------------------------------------------

# Same repo name, wrong owner: a fork with no kubernetes/kubernetes remote.
make_repo "fork-only" origin "git@github.com:someone/kubernetes.git"
# Name that starts with "kubernetes". Catches a missing "$" anchor.
make_repo "similar-name" origin "https://github.com/kubernetes/kubernetes-extras.git"
# Name that ends with "kubernetes". Catches matching on a bare suffix.
make_repo "prefix-name" origin "https://github.com/kubernetes/my-kubernetes.git"
# Right owner and name, wrong host.
make_repo "other-host" origin "https://gitlab.com/kubernetes/kubernetes.git"
# A repo with no remotes. make_repo always adds one, so we add a dummy and
# remove it straight away.
make_repo "no-remote" origin "https://github.com/kubernetes/website.git"
git -C "$ROOT/no-remote" remote remove origin
# A real match hidden inside node_modules. It should be skipped because the
# script prunes node_modules entirely.
make_repo "node_modules/k8s" origin "https://github.com/kubernetes/kubernetes.git"

# ---------------------------------------------------------------------------
# Run the script and check the results.
# ---------------------------------------------------------------------------

output=$("$SCRIPT" "$ROOT")
status=$?

# Every repo from the "should find" section.
for p in kubernetes renamed-https-dotgit renamed-scp renamed-ssh-url \
  trailing-slash mixed-case with-userinfo .hidden/deeply/nested/k8s \
  "path with spaces" fork-with-upstream k8s-worktree; do
  assert_found "$p"
done

# Every decoy from the "should not find" section.
for p in fork-only similar-name prefix-name other-host no-remote node_modules/k8s; do
  assert_not_found "$p"
done

# We found matches above, so the script should have exited 0.
if [[ $status -eq 0 ]]; then echo "ok: exit 0 when found"; else
  echo "FAIL: expected exit 0, got $status"; failures=$((failures + 1)); fi

# An empty folder has nothing to find, so the script should exit 1.
empty=$(mktemp -d)
"$SCRIPT" "$empty" >/dev/null
status=$?
rm -rf "$empty"
if [[ $status -eq 1 ]]; then echo "ok: exit 1 when nothing found"; else
  echo "FAIL: expected exit 1, got $status"; failures=$((failures + 1)); fi

# ---------------------------------------------------------------------------
# Override TARGET_REPO to search for a different repo.
# ---------------------------------------------------------------------------

# A repo with dots in its name, plus a decoy that only matches if those dots
# are treated as regex "any character" instead of literal dots.
make_repo "other-repo" origin "git@github.com:vercel/next.js.git"
make_repo "dot-decoy" origin "git@github.com:vercel/nextxjs.git"

# Mixed case checks that the target gets lowercased just like the URLs do.
output=$(TARGET_REPO=Vercel/Next.js "$SCRIPT" "$ROOT")

assert_found "other-repo"
assert_not_found "dot-decoy"
# The default repo's clones shouldn't show up once we've overridden it.
assert_not_found "kubernetes"
assert_not_found "renamed-scp"

echo
if [[ $failures -eq 0 ]]; then echo "All tests passed"; else echo "$failures failure(s)"; exit 1; fi
