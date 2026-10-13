# find-clones

Finds every local clone of a GitHub repo, no matter what folder name it was cloned as. It matches on the repo's remote URLs rather than the folder name, so `~/src/k8s` and `~/.worktrees/My Projects/fix-flaky-test` are found just the same as `~/Projects/kubernetes`.

By default it looks for [kubernetes/kubernetes](https://github.com/kubernetes/kubernetes).

## Usage

```bash
# Search your home directory for kubernetes/kubernetes
./find-clones.sh

# Search specific folders instead
./find-clones.sh ~/Projects /opt/src

# Search for a different repo
TARGET_REPO=golang/go ./find-clones.sh
```

It prints one repo path per line and exits `0` if it found at least one clone, or `1` if it found none. That makes it easy to use from other scripts:

```bash
if ./find-clones.sh >/dev/null; then
  echo "You've got kubernetes checked out somewhere"
fi

./find-clones.sh | while IFS= read -r repo; do
  git -C "$repo" fetch --quiet
done
```

### Configuration

| Variable      | Default                 | Description                          |
| ------------- | ----------------------- | ------------------------------------ |
| `TARGET_REPO` | `kubernetes/kubernetes` | The `owner/name` of the repo to find |

`TARGET_REPO` is case-insensitive, and dots in the name are matched literally.

## How It Works

1. Walks each search folder looking for anything named `.git`.
2. Treats the folder containing each `.git` as a candidate repo.
3. Reads every remote URL from that repo's config (`origin`, `upstream`, or any other name).
4. Normalizes each URL: lowercases it and strips any trailing `/` or `.git`.
5. Prints the repo path if any remote points at `github.com/$TARGET_REPO`.

### What It Matches

All of these URL forms count as the same repo:

```
https://github.com/kubernetes/kubernetes
https://github.com/kubernetes/kubernetes.git
https://someone@github.com/kubernetes/kubernetes.git
git@github.com:kubernetes/kubernetes.git
ssh://git@github.com/kubernetes/kubernetes.git
```

It also finds:

- **Worktrees and submodules:** their `.git` is a file rather than a folder, and both kinds are picked up.
- **Forks with an upstream:** a fork whose `origin` is your copy but whose `upstream` is the target repo.
- **Hidden folders:** clones under dot folders like `~/.config`.
- **Awkward paths:** paths with spaces or other unusual characters.

### What It Skips

To keep things fast and avoid macOS permission noise, it never searches inside:

- `~/Library`
- `node_modules`
- `.Trash`
- `.git` folders themselves

### Limitations

- **GitHub only:** remotes on other hosts, such as GitLab, aren't matched.
- **No bare clones:** bare repos don't have a `.git` entry, so they aren't found.
- **Needs a remote:** a clone whose remote pointing at the target repo was removed or changed won't be found.
- **Speed:** searching all of `$HOME` can take around 30 seconds. Pass specific folders to speed it up.

## Requirements

- bash 3.2 or newer (the version that ships with macOS is fine)
- git
- `find`, `tr`, and `dirname` (standard on macOS and Linux)

## Running the Tests

```bash
./find-clones_test.sh
```

The tests build a set of throwaway repos in a temp folder, run the script against it, and check that every expected clone is found and every decoy is skipped. The temp folder is deleted when the tests finish. If you have [ShellCheck](https://www.shellcheck.net/) installed, it's worth running too:

```bash
shellcheck find-clones.sh find-clones_test.sh
```
