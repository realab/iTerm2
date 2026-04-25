# Build Locally

This is the local build flow for getting the latest upstream `master`,
building a Deployment app, ad-hoc signing it, and running it locally.
It is for local use only, not for release distribution or notarization.

## 1. Check The Worktree

Read the repo guidance first:

```sh
sed -n '1,220p' CLAUDE.md
```

Check branch, remotes, and local changes:

```sh
git status --short --branch
git remote -v
git branch --show-current
```

If there are local modifications, preserve them before merging:

```sh
git stash push -m pre-upstream-master-merge
```

## 2. Fetch And Merge Upstream

Fetch the latest upstream master:

```sh
git fetch upstream master
```

Inspect divergence if useful:

```sh
git rev-list --left-right --count master...upstream/master
git log --oneline --decorate --left-right --graph --max-count=20 master...upstream/master
```

Merge upstream into local `master`:

```sh
git merge upstream/master
```

If the sandbox blocks `.git` ref updates, rerun the merge with elevated
permissions rather than trying to edit `.git` manually.

Restore the preserved local changes:

```sh
git stash pop stash@{0}
```

Confirm the merge and worktree state:

```sh
git status --short --branch
git log -1 --oneline --decorate
git rev-parse --short upstream/master
```

## 3. Build Deployment

Use a fresh, explicit build directory under `/tmp`:

```sh
env SIGNED=1 UNIVERSAL=1 BUILD_DIR=/tmp/iterm2-build-prod-signed make Deployment
```

Expected app path:

```sh
/tmp/iterm2-build-prod-signed/Deployment/iTerm2.app
```

The build should end with:

```text
** BUILD SUCCEEDED **
```

Check version and architecture:

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /tmp/iterm2-build-prod-signed/Deployment/iTerm2.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /tmp/iterm2-build-prod-signed/Deployment/iTerm2.app/Contents/Info.plist
lipo -archs /tmp/iterm2-build-prod-signed/Deployment/iTerm2.app/Contents/MacOS/iTerm2
```

## 4. Ad-Hoc Sign For Local Run

The local machine may not have the project Developer ID certificate.
For local execution, re-sign the built app ad-hoc:

```sh
codesign --force --deep --sign - /tmp/iterm2-build-prod-signed/Deployment/iTerm2.app
```

Verify it:

```sh
codesign --verify --deep --strict --verbose=4 /tmp/iterm2-build-prod-signed/Deployment/iTerm2.app
codesign -dv --verbose=4 /tmp/iterm2-build-prod-signed/Deployment/iTerm2.app
```

Expected verification includes:

```text
valid on disk
satisfies its Designated Requirement
Signature=adhoc
```

## 5. Run Locally

Launch a new instance of the locally signed build:

```sh
open -n /tmp/iterm2-build-prod-signed/Deployment/iTerm2.app
```

If sandboxing blocks `open`, rerun that command with elevated permission.

## Notes From The Current Machine

- `upstream` is `git@github.com:gnachman/iTerm2.git`.
- `origin` is `git@github.com:realab/iTerm2.git`.
- `master` may remain ahead of `origin/master` after merging upstream.
- Existing local Xcode project/workspace changes should be preserved and
  restored; do not discard them unless explicitly asked.
- A real release signature requires an installed valid Developer ID or
  suitable Mac signing certificate. Ad-hoc signing is enough for local run.
