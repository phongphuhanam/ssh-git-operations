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
| `sshd-toggle-password` | Flips `PasswordAuthentication` in `/etc/ssh/sshd_config` and reloads sshd, on whatever machine it's run on. Needs the plugin loaded there — for a one-off toggle without that, use `sshd-toggle-password.sh` instead (see below) |

`<host>` accepts either `user@host /path` (space-separated) or scp-style
`user@host:/path`.

`ssh-gh-remote-push`/`-pull`/`-fetch`/`-clone`/`-submodule-update` all also
accept `--forward-agent[=<ssh-config-host>]` (anywhere in the args), for when
the *remote* repo's (or a submodule's) own `origin` is an SSH URL
(`git@github.com:...`) rather than HTTPS — the token/credential-helper trick
only authenticates HTTPS remotes. `<ssh-config-host>` names a `Host` entry in
the caller's `~/.ssh/config`; its `IdentityFile` gets loaded into the local
ssh-agent (starting one first if none is running) and forwarded (`ssh -A`)
for that one call only. Only `--forward-agent=<host>` (the `=` form) takes an
explicit value — there's no space-separated two-token form, since the
positional args around it are themselves optional and a bare word after the
flag would be ambiguous.

Omitting the value (`--forward-agent` alone, or `--forward-agent=` with
nothing after the `=`) auto-picks the one `~/.ssh/config` `Host` entry whose
`HostName` is `github.com`; it errors out asking for an explicit
`--forward-agent=<host>` if there's zero or more than one such entry (e.g.
separate personal/work GitHub identities) rather than guessing. Prefer the
bare form when you don't already know the right alias; only name one
explicitly if auto-pick errors out or the user names a specific identity.

It's off by default — **don't add it speculatively**; only reach for it when
a push/pull/fetch/clone/submodule-update fails because the remote's origin
turns out to be an SSH URL, or the user says so upfront. Forwarding exposes
a live agent socket to the remote host for the connection's duration (root,
or the same remote account, could use it to sign requests as the caller) —
a materially different, larger exposure than the token handling, so don't
suggest it against a host the user hasn't indicated they trust.

## 2. Picking the right one

- "push/sync my changes to X" → `ssh-gh-remote-push` (or `-fetch` if they just
  want the remote aware of upstream without merging)
- "clone/set up this repo on X" → `ssh-gh-remote-clone`
- "commit this on X as me" / "the remote has no git identity configured" →
  `ssh-gh-remote-commit`
- "update submodules on X" → `ssh-gh-remote-submodule-update`
- "what repos are on X" → `scp-git-aware`
- a push/pull/fetch/clone/submodule-update fails with an SSH auth error (not
  an HTTPS/token one), or the user mentions the repo/submodule is cloned via
  SSH → retry the same command with `--forward-agent` (bare, to auto-pick),
  or `--forward-agent=<ssh-config-host>` if auto-pick errors out or the user
  names a specific identity
- "toggle password auth on X" (X = a remote host, and the plugin isn't
  loaded there) → pipe the standalone script through ssh in one line,
  rather than trying to ssh in and call the `sshd-toggle-password` function
  (which requires the plugin to already be sourced on that host):
  ```bash
  curl -fsSL https://raw.githubusercontent.com/phongphuhanam/ssh-git-operations/main/sshd-toggle-password.sh | ssh user@host bash
  ```
  This needs passwordless sudo on the remote account (no tty for a sudo
  prompt over a non-interactive ssh pipe). If that's not set up, `ssh` in
  interactively and run the one-liner locally on that host instead:
  `curl -fsSL .../sshd-toggle-password.sh | bash`.
- "toggle password auth" with no remote host mentioned → run
  `sshd-toggle-password` (if the plugin's loaded here) or the `.sh` one-liner
  directly on this machine.

## 3. Don't re-derive what's already solved

The credential-helper reset-then-set pattern, the stdin-delivery trick, and
the residual-exposure caveats (token briefly visible in the remote `git`
process's own argv while it runs) are already documented and handled inside
`ssh-git-operations.plugin.zsh` and `README.md`. Read those if you need the
exact mechanism, but don't reimplement it — call the function.
