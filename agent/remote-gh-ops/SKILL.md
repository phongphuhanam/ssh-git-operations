---
name: remote-gh-ops
description: Use when the user wants to push/pull/fetch/clone/commit a git repo, sync submodules, or toggle SSH password auth on a remote machine reached via ssh (e.g. "push this on msis39", "clone this repo onto the GPU box", "commit these changes on the server as me"). Prefer the ssh-git-operations plugin's pre-built functions over hand-rolling the ssh + gh-token dance.
---

# Remote git operations via the ssh-git-operations plugin

This repo ships an Oh My Zsh plugin (`ssh-git-operations.plugin.zsh`) with
ready-made shell functions for the common remote-git-over-ssh tasks. If the
user's request is about running git on a machine reached over `ssh`, check
whether these functions are available **before** manually reconstructing an
`ssh ... "git -c credential.helper=..."` one-liner from scratch.

## 0. Check availability

```bash
type ssh-gh-remote-push &>/dev/null && echo available
```

If not found but the plugin file is reachable (this repo, or already
installed under `${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/ssh-git-operations`),
source it directly for the current session instead of re-deriving the
token-passing logic by hand:

```bash
source /path/to/ssh-git-operations.plugin.zsh
```

If it truly isn't available and can't be sourced, fall back to the manual
token-borrowing technique (see the `remote-git-sync` skill) — but that should
be the exception, not the default.

## 1. Command reference

All of these get the GitHub token locally via `gh auth token` and deliver any
remote script over the `ssh` session's **stdin** to `bash -s`, never as a
command-line argument — so the token never appears in `ps`/argv on either
end. Full rationale in this repo's `README.md` ("How It Works").

| Command | Purpose |
|---|---|
| `ssh-gh-remote-push <host>[:/path]` | Push the current branch (detected on the remote) |
| `ssh-gh-remote-pull <host>[:/path]` | Pull the current branch |
| `ssh-gh-remote-fetch <host>[:/path]` | Fetch without merging (safest default for "sync") |
| `ssh-gh-remote-clone <host> <owner/repo\|url> [dest]` | Clone onto the remote; re-running it `pull --ff-only`s an existing clone instead of failing |
| `ssh-gh-remote-submodule-update <host>[:/path]` | `git submodule sync --recursive` + `update --init --recursive`, token-authenticated; also exports `GH_TOKEN` remotely for hooks that read it directly |
| `ssh-gh-remote-commit <host>[:/path] -m "msg" [pathspec...]` | Stage + commit on the remote using **your local** `git config user.name`/`user.email`, not the remote's. No token involved — it's a local commit on that host. Follow with `ssh-gh-remote-push` to publish |
| `scp-git-aware <host>` | List git repos found on the remote, for discovery |
| `sshd-toogle-password` | **Local only** — flips `PasswordAuthentication` in `/etc/ssh/sshd_config` on the machine you're currently on and reloads sshd. Not for the remote target host; don't use this to touch a remote's sshd config |

`<host>` accepts either `user@host /path` (space-separated) or scp-style
`user@host:/path`.

## 2. Picking the right one

- "push/sync my changes to X" → `ssh-gh-remote-push` (or `-fetch` if they just
  want the remote aware of upstream without merging)
- "clone/set up this repo on X" → `ssh-gh-remote-clone`
- "commit this on X as me" / "the remote has no git identity configured" →
  `ssh-gh-remote-commit`
- "update submodules on X" → `ssh-gh-remote-submodule-update`
- "what repos are on X" → `scp-git-aware`
- Toggling password login is about the **local** host's sshd, not a remote
  target — don't reach for `sshd-toogle-password` when the user says "on the
  remote"; that function takes no host argument by design.

## 3. Don't re-derive what's already solved

The credential-helper reset-then-set pattern, the stdin-delivery trick, and
the residual-exposure caveats (token briefly visible in the remote `git`
process's own argv while it runs) are already documented and handled inside
`ssh-git-operations.plugin.zsh` and `README.md`. Read those if you need the
exact mechanism, but don't reimplement it — call the function.
