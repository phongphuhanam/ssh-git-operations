#!/usr/bin/env zsh
# ssh-git-operations.plugin.zsh
# Oh My Zsh plugin for secure git push/pull/fetch over SSH with GitHub token authentication

# Verify gh CLI is available
if ! command -v gh &> /dev/null; then
    echo "Warning: GitHub CLI (gh) not found. ssh-git-operations requires 'gh' to be installed."
    echo "Install it from: https://github.com/cli/cli"
    return 1
fi

# Load completion file - automatically loaded by Oh My Zsh
# The _ssh-git-operations file will be found in the plugin directory

# Helper function to get GitHub token
_ssh_git_get_token() {
    gh auth token 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "Error: Failed to retrieve GitHub token. Ensure you're logged in with 'gh auth login'" >&2
        return 1
    fi
}

# Single-quote a string for safe literal embedding into a remote shell
# script that is assembled locally by interpolating ${vars} into an
# unquoted heredoc (see _ssh_git_remote_run's stdin-delivery notes below).
# Needed wherever the interpolated value is arbitrary user input (commit
# messages, pathspecs, git identity) rather than a token, which never
# contains shell metacharacters in practice.
_ssh_git_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# Finds the single ~/.ssh/config Host entry whose HostName resolves to
# github.com, for auto-picking an identity when --forward-agent is given
# with no explicit alias. Errors (rather than guessing) unless there's
# exactly one match.
_ssh_git_auto_forward_host() {
    if [[ ! -f "$HOME/.ssh/config" ]]; then
        echo "Error: --forward-agent given with no host, and no ~/.ssh/config to auto-pick a github.com entry from. Use --forward-agent=<host> instead." >&2
        return 1
    fi

    local -a candidates
    candidates=(${(f)"$(awk '
        tolower($1) == "host" {
            if (host != "" && tolower(hostname) == "github.com" && host !~ /[*?]/) print host
            host = $2; hostname = ""; next
        }
        tolower($1) == "hostname" { hostname = $2 }
        END {
            if (host != "" && tolower(hostname) == "github.com" && host !~ /[*?]/) print host
        }
    ' "$HOME/.ssh/config" 2>/dev/null)"})

    if [ ${#candidates} -eq 0 ]; then
        echo "Error: no Host entry in ~/.ssh/config has HostName github.com; can't auto-pick one. Use --forward-agent=<host> instead." >&2
        return 1
    elif [ ${#candidates} -gt 1 ]; then
        echo "Error: multiple ~/.ssh/config Host entries resolve to github.com (${candidates[*]}); can't auto-pick. Use --forward-agent=<host> instead." >&2
        return 1
    fi

    echo "${candidates[1]}"
}

# Resolves the IdentityFile configured for a named `Host` entry in the
# caller's ~/.ssh/config, and loads it into the local ssh-agent (via
# ssh-add) if it isn't already there. Used before agent-forwarded
# connections, so the identity the caller asked for is guaranteed to be
# present in the agent that gets forwarded. Note this can't *exclude* other
# keys already loaded in the same agent — plain ssh-agent forwarding always
# exposes the whole agent, not a filtered subset; this only guarantees the
# requested one is included.
_ssh_git_load_forward_identity() {
    local host_alias=$1

    if [ "$host_alias" = "auto" ]; then
        host_alias=$(_ssh_git_auto_forward_host) || return 1
        echo "Auto-picked ssh-config Host '${host_alias}' (HostName github.com) for forwarding."
    fi

    if ! awk -v alias="$host_alias" '
        tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i == alias) found = 1 }
        END { exit !found }
    ' "$HOME/.ssh/config" 2>/dev/null; then
        echo "Error: no 'Host ${host_alias}' entry found in ~/.ssh/config" >&2
        return 1
    fi

    local identity_file
    identity_file=$(ssh -G "$host_alias" 2>/dev/null | awk '/^identityfile /{print $2; exit}')
    if [ -z "$identity_file" ]; then
        echo "Error: could not resolve an IdentityFile for Host '${host_alias}' in ~/.ssh/config" >&2
        return 1
    fi

    if ! command -v ssh-add &>/dev/null; then
        echo "Error: ssh-add not found; cannot load an identity for forwarding" >&2
        return 1
    fi

    # ssh-add/ssh -A are no-ops (or hard failures) without a running agent.
    # `ssh-add -l` exits 2 specifically when it can't reach one (as opposed
    # to 1, which means an agent is running but holds no keys yet) - start
    # one and export SSH_AUTH_SOCK/SSH_AGENT_PID into this shell so it's
    # there for both ssh-add below and the `ssh -A` forward itself. It's
    # left running for the rest of this shell session rather than torn back
    # down, so repeat --forward-agent calls don't re-spawn one each time.
    ssh-add -l &>/dev/null
    if [ $? -eq 2 ]; then
        if ! command -v ssh-agent &>/dev/null; then
            echo "Error: no ssh-agent running and ssh-agent not found to start one" >&2
            return 1
        fi
        echo "No ssh-agent running; starting one for this session..."
        eval "$(ssh-agent -s)" >/dev/null
    fi

    local fingerprint
    fingerprint=$(ssh-keygen -lf "$identity_file" 2>/dev/null | awk '{print $2}')
    if [ -n "$fingerprint" ] && ssh-add -l 2>/dev/null | grep -q "$fingerprint"; then
        return 0
    fi

    echo "Loading ${identity_file} into ssh-agent for forwarding (Host '${host_alias}')..."
    ssh-add "$identity_file"
}

# Strips a --forward-agent[=<host-alias>] flag out of "$@" if present,
# wherever it appears in the argument list. Sets _SSH_GIT_FORWARD_AGENT to:
# empty (flag not given), "auto" (bare --forward-agent, or --forward-agent=
# with nothing after the =, meaning auto-pick a github.com Host - see
# _ssh_git_auto_forward_host), or the given alias otherwise. Sets
# _SSH_GIT_ARGS to the remaining positional args. Used by each
# ssh-gh-remote-* wrapper before its normal positional-argument parsing.
#
# Deliberately no "--forward-agent <alias>" two-token form: since the
# surrounding positional args (host, path, ...) are themselves optional in
# most of these commands, a bare word right after the flag would be
# ambiguous between "the alias" and "the next positional arg" - only the
# unambiguous --forward-agent=<alias> form takes a value.
_ssh_git_strip_forward_agent_flag() {
    _SSH_GIT_FORWARD_AGENT=""
    _SSH_GIT_ARGS=()
    local arg
    for arg in "$@"; do
        case "$arg" in
            --forward-agent=*)
                _SSH_GIT_FORWARD_AGENT="${arg#*=}"
                [ -z "$_SSH_GIT_FORWARD_AGENT" ] && _SSH_GIT_FORWARD_AGENT="auto"
                ;;
            --forward-agent)
                _SSH_GIT_FORWARD_AGENT="auto"
                ;;
            *)
                _SSH_GIT_ARGS+=("$arg")
                ;;
        esac
    done
}

# Run a git operation (push/pull/fetch/clone) on the remote host.
#
# Security notes:
# - The whole script is sent over the SSH session's stdin to a plain
#   `bash -s` on the remote side, instead of being passed as a `ssh ... "<cmd>"`
#   command-line argument. That keeps the token out of the argv of the `ssh`
#   process (visible locally via `ps`) and the `bash -s` process (visible
#   remotely via `ps`) for as long as the connection is open.
# - `-c credential.helper= -c credential.helper='!f...'` resets the helper
#   chain before adding ours, so a pre-existing `credential.helper` on the
#   remote (e.g. `store` or a credential manager) is not also invoked to
#   cache the token to disk after a successful push/pull.
#
# Residual exposure (not eliminated by the above): once `git` itself runs,
# the token is still part of the `git -c credential.helper=...` argument, so
# the `git` process's own argv briefly contains it in plaintext and would be
# visible to `ps auxww` on the remote host (or root/same-user via
# /proc/<pid>/environ-equivalent) for the few seconds the command executes.
# Avoiding that entirely would require passing the token through a file
# descriptor/FIFO rather than a git -c value; ask if you want that hardening.
#
# Agent forwarding (opt-in via the forward_agent param, empty = off): needed
# only when the *remote* repo's own origin is an SSH URL (git@github.com:...)
# rather than HTTPS, since the token/credential-helper trick above only
# authenticates HTTPS remotes. forward_agent, when non-empty, is the name of
# a `Host` entry in the caller's ~/.ssh/config; its IdentityFile is loaded
# into the local ssh-agent (see _ssh_git_load_forward_identity) so that key
# is what's forwarded via `ssh -A`. Forwarding your local ssh-agent is a
# real exposure of its own — anyone with root (or the same remote user) can
# use the forwarded socket to sign requests as you for as long as the
# connection is open — which is why it defaults off and is scoped to one
# invocation, not left on in the caller's shell.
_ssh_git_remote_run() {
    local ssh_host=$1
    local repo_path=$2
    local operation=$3
    local token=$4

    case "$operation" in
        push|pull)
            local forward_agent=$5
            local ssh_opts=()
            if [ -n "$forward_agent" ]; then
                _ssh_git_load_forward_identity "$forward_agent" || return 1
                ssh_opts+=(-A)
            fi
            ssh "${ssh_opts[@]}" "$ssh_host" bash -s <<REMOTE_EOF
set -e
cd "${repo_path}" || { echo "Error: could not access ${repo_path} on ${ssh_host}" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Error: ${repo_path} is not a git repository" >&2; exit 1; }
branch=\$(git rev-parse --abbrev-ref HEAD)
git -c credential.helper= -c credential.helper='!f() { echo "username=x-access-token"; echo "password=${token}"; }; f' ${operation} origin "\$branch"
REMOTE_EOF
            ;;
        fetch)
            local forward_agent=$5
            local ssh_opts=()
            if [ -n "$forward_agent" ]; then
                _ssh_git_load_forward_identity "$forward_agent" || return 1
                ssh_opts+=(-A)
            fi
            ssh "${ssh_opts[@]}" "$ssh_host" bash -s <<REMOTE_EOF
set -e
cd "${repo_path}" || { echo "Error: could not access ${repo_path} on ${ssh_host}" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Error: ${repo_path} is not a git repository" >&2; exit 1; }
git -c credential.helper= -c credential.helper='!f() { echo "username=x-access-token"; echo "password=${token}"; }; f' fetch origin
REMOTE_EOF
            ;;
        submodule-update)
            # GH_TOKEN is exported for submodule hooks/scripts that read it
            # directly, alongside the credential helper git itself uses to
            # authenticate each submodule fetch.
            local forward_agent=$5
            local ssh_opts=()
            if [ -n "$forward_agent" ]; then
                _ssh_git_load_forward_identity "$forward_agent" || return 1
                ssh_opts+=(-A)
            fi
            ssh "${ssh_opts[@]}" "$ssh_host" bash -s <<REMOTE_EOF
set -e
cd "${repo_path}" || { echo "Error: could not access ${repo_path} on ${ssh_host}" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Error: ${repo_path} is not a git repository" >&2; exit 1; }
export GH_TOKEN="${token}"
git submodule sync --recursive
git -c credential.helper= -c credential.helper='!f() { echo "username=x-access-token"; echo "password=${token}"; }; f' submodule update --init --recursive
REMOTE_EOF
            ;;
        clone)
            # Extra parameter: destination directory (optional; defaults to the
            # repository name in the remote current directory).
            # Destination that already holds a git clone is updated in place
            # (pull --ff-only) instead of failing with "already exists".
            # An existing empty directory is used as the clone target.
            # An existing non-empty, non-repo directory is an error.
            local dest_dir=$5
            local forward_agent=$6
            local ssh_opts=()
            if [ -n "$forward_agent" ]; then
                _ssh_git_load_forward_identity "$forward_agent" || return 1
                ssh_opts+=(-A)
            fi
            ssh "${ssh_opts[@]}" "$ssh_host" bash -s <<REMOTE_EOF
set -e
url="${repo_path}"
dest="${dest_dir}"
if [ -d "\$dest" ] && git -C "\$dest" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Repository already exists at \$dest — updating in place instead of re-cloning."
    branch=\$(git -C "\$dest" rev-parse --abbrev-ref HEAD)
    git -C "\$dest" -c credential.helper= -c credential.helper='!f() { echo "username=x-access-token"; echo "password=${token}"; }; f' pull --ff-only origin "\$branch"
else
    if [ -d "\$dest" ] && [ -n "\$(ls -A "\$dest" 2>/dev/null)" ]; then
        echo "Error: \$dest exists on ${ssh_host} and is not a git repository; refusing to clone into it." >&2
        exit 1
    fi
    mkdir -p "\$(dirname "\$dest")"
    git -c credential.helper= -c credential.helper='!f() { echo "username=x-access-token"; echo "password=${token}"; }; f' clone "\$url" "\$dest"
fi
REMOTE_EOF
            ;;
        *)
            echo "Usage: _ssh_git_remote_run <user@host> <repo_path> <push|pull|fetch|clone|submodule-update> <token> [forward_agent]" >&2
            return 1
            ;;
    esac
}

# ssh-gh-remote-push - Push current branch to GitHub over SSH
# Usage: ssh-gh-remote-push user@host:/path  (scp-style with colon)
#        ssh-gh-remote-push user@host /path   (space-separated)
# Add --forward-agent[=<ssh-config-host>] to also forward your ssh-agent (with
# that Host entry's identity loaded), for when the *remote* repo's own
# origin is itself an SSH URL rather than HTTPS. Omit the value to
# auto-pick the one ~/.ssh/config Host whose HostName is github.com (errors
# if there's zero or more than one).
ssh-gh-remote-push() {
    _ssh_git_strip_forward_agent_flag "$@"
    set -- "${_SSH_GIT_ARGS[@]}"
    local forward_agent=$_SSH_GIT_FORWARD_AGENT

    local ssh_host=$1
    local repo_path=$2

    if [ -z "$ssh_host" ]; then
        echo "Usage: ssh-gh-remote-push <user@host>:[/path] or <user@host> [/path] [--forward-agent[=<ssh-config-host>]]" >&2
        echo "Examples:" >&2
        echo "  ssh-gh-remote-push dev@server.com:/home/user/myproject" >&2
        echo "  ssh-gh-remote-push dev@server.com /home/user/myproject" >&2
        echo "  ssh-gh-remote-push dev@server.com /home/user/myproject --forward-agent=github-work" >&2
        echo "  ssh-gh-remote-push dev@server.com /home/user/myproject --forward-agent  # auto-picks a github.com Host" >&2
        return 1
    fi

    # Handle scp-style syntax with colon (user@host:/path)
    if [[ "$ssh_host" == *:* ]]; then
        repo_path="${ssh_host#*:}"
        ssh_host="${ssh_host%:*}"
    fi

    # Default to current directory if no path provided
    repo_path=${repo_path:-.}

    local token
    token=$(_ssh_git_get_token) || return 1

    echo "Pushing to GitHub via SSH..."
    _ssh_git_remote_run "$ssh_host" "$repo_path" push "$token" "$forward_agent"
}

# ssh-gh-remote-pull - Pull from GitHub over SSH
# Usage: ssh-gh-remote-pull user@host:/path  (scp-style with colon)
#        ssh-gh-remote-pull user@host /path   (space-separated)
# Add --forward-agent[=<ssh-config-host>] to also forward your ssh-agent (with
# that Host entry's identity loaded), for when the *remote* repo's own
# origin is itself an SSH URL rather than HTTPS. Omit the value to
# auto-pick the one ~/.ssh/config Host whose HostName is github.com (errors
# if there's zero or more than one).
ssh-gh-remote-pull() {
    _ssh_git_strip_forward_agent_flag "$@"
    set -- "${_SSH_GIT_ARGS[@]}"
    local forward_agent=$_SSH_GIT_FORWARD_AGENT

    local ssh_host=$1
    local repo_path=$2

    if [ -z "$ssh_host" ]; then
        echo "Usage: ssh-gh-remote-pull <user@host>:[/path] or <user@host> [/path] [--forward-agent[=<ssh-config-host>]]" >&2
        echo "Examples:" >&2
        echo "  ssh-gh-remote-pull dev@server.com:/home/user/myproject" >&2
        echo "  ssh-gh-remote-pull dev@server.com /home/user/myproject" >&2
        echo "  ssh-gh-remote-pull dev@server.com /home/user/myproject --forward-agent=github-work" >&2
        echo "  ssh-gh-remote-pull dev@server.com /home/user/myproject --forward-agent  # auto-picks a github.com Host" >&2
        return 1
    fi

    # Handle scp-style syntax with colon (user@host:/path)
    if [[ "$ssh_host" == *:* ]]; then
        repo_path="${ssh_host#*:}"
        ssh_host="${ssh_host%:*}"
    fi

    # Default to current directory if no path provided
    repo_path=${repo_path:-.}

    local token
    token=$(_ssh_git_get_token) || return 1

    echo "Pulling from GitHub via SSH..."
    _ssh_git_remote_run "$ssh_host" "$repo_path" pull "$token" "$forward_agent"
}

# ssh-gh-remote-fetch - Fetch from GitHub over SSH
# Usage: ssh-gh-remote-fetch user@host:/path  (scp-style with colon)
#        ssh-gh-remote-fetch user@host /path   (space-separated)
# Add --forward-agent[=<ssh-config-host>] to also forward your ssh-agent (with
# that Host entry's identity loaded), for when the *remote* repo's own
# origin is itself an SSH URL rather than HTTPS. Omit the value to
# auto-pick the one ~/.ssh/config Host whose HostName is github.com (errors
# if there's zero or more than one).
ssh-gh-remote-fetch() {
    _ssh_git_strip_forward_agent_flag "$@"
    set -- "${_SSH_GIT_ARGS[@]}"
    local forward_agent=$_SSH_GIT_FORWARD_AGENT

    local ssh_host=$1
    local repo_path=$2

    if [ -z "$ssh_host" ]; then
        echo "Usage: ssh-gh-remote-fetch <user@host>:[/path] or <user@host> [/path] [--forward-agent[=<ssh-config-host>]]" >&2
        echo "Examples:" >&2
        echo "  ssh-gh-remote-fetch dev@server.com:/home/user/myproject" >&2
        echo "  ssh-gh-remote-fetch dev@server.com /home/user/myproject" >&2
        echo "  ssh-gh-remote-fetch dev@server.com /home/user/myproject --forward-agent=github-work" >&2
        echo "  ssh-gh-remote-fetch dev@server.com /home/user/myproject --forward-agent  # auto-picks a github.com Host" >&2
        return 1
    fi

    # Handle scp-style syntax with colon (user@host:/path)
    if [[ "$ssh_host" == *:* ]]; then
        repo_path="${ssh_host#*:}"
        ssh_host="${ssh_host%:*}"
    fi

    # Default to current directory if no path provided
    repo_path=${repo_path:-.}

    local token
    token=$(_ssh_git_get_token) || return 1

    echo "Fetching from GitHub via SSH..."
    _ssh_git_remote_run "$ssh_host" "$repo_path" fetch "$token" "$forward_agent"
}

# ssh-gh-remote-clone - Clone a repository from GitHub onto a remote machine over SSH
# The repository is an owner/repo reference or an HTTPS URL (a GitHub repo, NOT
# a path on the remote machine). The destination directory on the remote is
# optional.
#
# Usage:
#   ssh-gh-remote-clone user@host owner/repo [dest]
#   ssh-gh-remote-clone user@host https://github.com/owner/repo.git [dest]
#   ssh-gh-remote-clone user@host:/path/<dest> owner/repo|url   (scp-style dest)
#   ssh-gh-remote-clone user@host:owner/repo                    (scp-style repo)
# Add --forward-agent[=<ssh-config-host>] to also forward your ssh-agent (with
# that Host entry's identity loaded), for when the repo being cloned onto
# the remote itself needs an SSH-authenticated submodule/hook, etc. Omit
# the value to auto-pick the one ~/.ssh/config Host whose HostName is
# github.com (errors if there's zero or more than one).
ssh-gh-remote-clone() {
    _ssh_git_strip_forward_agent_flag "$@"
    set -- "${_SSH_GIT_ARGS[@]}"
    local forward_agent=$_SSH_GIT_FORWARD_AGENT

    local ssh_host=$1
    local repo=$2
    local dest_dir=$3

    # Split scp-style "host:extra" syntax (a colon in arg 1 means host:tail).
    # Skip URLs, which themselves contain a colon (https://...). The tail is a
    # destination path when it looks like one (arg 2 then supplies the repo), or
    # the repository itself when no repo argument is given.
    if [[ $ssh_host == *:* && $ssh_host != http://* && $ssh_host != https://* ]]; then
        local host_part=${ssh_host%%:*}
        local tail=${ssh_host#*:}
        ssh_host=$host_part
        if [[ $tail == /* || $tail == "~"* || $tail == ./* ]]; then
            [ -z "$dest_dir" ] && dest_dir=$tail
        elif [ -n "$repo" ]; then
            # repo already supplied as arg 2, so a plain relative tail
            # (e.g. "newproj") is a destination directory name, not a repo.
            [ -z "$dest_dir" ] && dest_dir=$tail
        else
            repo=$tail
        fi
    fi

    if [ -z "$ssh_host" ] || [ -z "$repo" ]; then
        echo "Usage: ssh-gh-remote-clone <user@host> <owner/repo|url> [dest]" >&2
        echo "       ssh-gh-remote-clone <user@host>:/<dest-path> <owner/repo|url>" >&2
        echo "Examples:" >&2
        echo "  ssh-gh-remote-clone dev@server.com owner/myproject" >&2
        echo "  ssh-gh-remote-clone host:/home/user/proj https://github.com/owner/myproject.git" >&2
        echo "  ssh-gh-remote-clone dev@server.com https://github.com/owner/myproject.git" >&2
        return 1
    fi

    # Normalize the repository reference to a cloneable HTTPS URL
    if [[ "$repo" == http://* || "$repo" == https://* ]]; then
        local clone_url=$repo
        [[ "$clone_url" == *.git ]] || clone_url="${clone_url%/}.git"
    else
        # owner/repo reference
        clone_url="https://github.com/${repo%/}.git"
    fi

    # Default destination to the repository name in the current remote directory
    local repo_name=${clone_url##*/}
    repo_name=${repo_name%.git}
    dest_dir=${dest_dir:-$repo_name}

    local token
    token=$(_ssh_git_get_token) || return 1

    echo "Cloning ${clone_url} on ${ssh_host} to ${dest_dir} via SSH..."
    _ssh_git_remote_run "$ssh_host" "$clone_url" clone "$token" "$dest_dir" "$forward_agent"
}

# ssh-gh-remote-submodule-update - Sync and update submodules on a remote repo
# Runs `git submodule sync --recursive` followed by
# `git submodule update --init --recursive`, authenticating each submodule
# fetch with your local GitHub token (also exported remotely as GH_TOKEN, for
# submodule hooks/scripts that expect that env var directly).
# Usage: ssh-gh-remote-submodule-update user@host:/path  (scp-style with colon)
#        ssh-gh-remote-submodule-update user@host /path   (space-separated)
# Add --forward-agent[=<ssh-config-host>] to also forward your ssh-agent (with
# that Host entry's identity loaded) — needed when one or more submodules
# are themselves declared with an SSH URL rather than HTTPS.
ssh-gh-remote-submodule-update() {
    _ssh_git_strip_forward_agent_flag "$@"
    set -- "${_SSH_GIT_ARGS[@]}"
    local forward_agent=$_SSH_GIT_FORWARD_AGENT

    local ssh_host=$1
    local repo_path=$2

    if [ -z "$ssh_host" ]; then
        echo "Usage: ssh-gh-remote-submodule-update <user@host>:[/path] or <user@host> [/path] [--forward-agent[=<ssh-config-host>]]" >&2
        echo "Examples:" >&2
        echo "  ssh-gh-remote-submodule-update dev@server.com:/home/user/myproject" >&2
        echo "  ssh-gh-remote-submodule-update dev@server.com /home/user/myproject" >&2
        echo "  ssh-gh-remote-submodule-update dev@server.com /home/user/myproject --forward-agent=github-work" >&2
        echo "  ssh-gh-remote-submodule-update dev@server.com /home/user/myproject --forward-agent  # auto-picks a github.com Host" >&2
        return 1
    fi

    # Handle scp-style syntax with colon (user@host:/path)
    if [[ "$ssh_host" == *:* ]]; then
        repo_path="${ssh_host#*:}"
        ssh_host="${ssh_host%:*}"
    fi

    # Default to current directory if no path provided
    repo_path=${repo_path:-.}

    local token
    token=$(_ssh_git_get_token) || return 1

    echo "Syncing and updating submodules via SSH..."
    _ssh_git_remote_run "$ssh_host" "$repo_path" submodule-update "$token" "$forward_agent"
}

# ssh-gh-remote-commit - Stage and commit changes on a remote repo using
# *your local machine's* git identity (user.name/user.email), instead of
# whatever (if anything) is configured on the remote. The identity is
# passed per-commit via `git -c`; nothing is written to the remote's git
# config. No GitHub token is involved — this only commits locally on the
# remote host. Follow up with ssh-gh-remote-push to publish it.
#
# Usage:
#   ssh-gh-remote-commit <user@host>:[/path] -m "<message>" [pathspec...]
#   ssh-gh-remote-commit <user@host> [/path] -m "<message>" [pathspec...]
# With no pathspec, all changes in the repo are staged (like `git add -A`).
ssh-gh-remote-commit() {
    local ssh_host=$1
    local repo_path=""

    if [ -z "$ssh_host" ]; then
        echo "Usage: ssh-gh-remote-commit <user@host>:[/path] -m \"<message>\" [pathspec...]" >&2
        echo "       ssh-gh-remote-commit <user@host> [/path] -m \"<message>\" [pathspec...]" >&2
        echo "Examples:" >&2
        echo "  ssh-gh-remote-commit dev@server.com:/home/user/myproject -m \"fix bug\" src/foo.py" >&2
        echo "  ssh-gh-remote-commit dev@server.com /home/user/myproject -m \"fix bug\"" >&2
        return 1
    fi

    # Handle scp-style syntax with colon (user@host:/path); otherwise the
    # next positional arg is the path, unless it's already the -m flag
    # (meaning no path was given and it defaults to the remote's cwd).
    if [[ "$ssh_host" == *:* ]]; then
        repo_path="${ssh_host#*:}"
        ssh_host="${ssh_host%:*}"
        shift 1
    elif [ "$2" != "-m" ]; then
        repo_path=$2
        shift 2
    else
        shift 1
    fi

    repo_path=${repo_path:-.}

    if [ "$1" != "-m" ] || [ -z "$2" ]; then
        echo "Error: a commit message is required, e.g. -m \"message\"" >&2
        return 1
    fi
    local message=$2
    shift 2

    local local_name local_email
    local_name=$(git config --get user.name 2>/dev/null)
    local_email=$(git config --get user.email 2>/dev/null)
    if [ -z "$local_name" ] || [ -z "$local_email" ]; then
        echo "Error: local git identity not configured. Run:" >&2
        echo "  git config --global user.name \"Your Name\"" >&2
        echo "  git config --global user.email you@example.com" >&2
        return 1
    fi

    local quoted_paths="."
    if [ $# -gt 0 ]; then
        quoted_paths=""
        local p
        for p in "$@"; do
            quoted_paths="${quoted_paths} $(_ssh_git_quote "$p")"
        done
    fi

    echo "Committing on ${ssh_host} as ${local_name} <${local_email}>..."
    ssh "$ssh_host" bash -s <<REMOTE_EOF
set -e
cd "${repo_path}" || { echo "Error: could not access ${repo_path} on ${ssh_host}" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Error: ${repo_path} is not a git repository" >&2; exit 1; }
git add -- ${quoted_paths}
git -c user.name=$(_ssh_git_quote "$local_name") -c user.email=$(_ssh_git_quote "$local_email") commit -m $(_ssh_git_quote "$message")
REMOTE_EOF
}

# scp-git-aware - Enhanced scp with git-aware directory autocompletion
# Usage: scp-git-aware user@host
scp-git-aware() {
    local ssh_host=$1

    if [ -z "$ssh_host" ]; then
        echo "Usage: scp-git-aware <user@host>" >&2
        echo "Lists directories with git repositories for easy navigation" >&2
        return 1
    fi

    echo "Scanning for git repositories on $ssh_host..."
    ssh "$ssh_host" "find ~/ -maxdepth 3 -type d -name '.git' 2>/dev/null | sed 's|/.git||' | head -20"
}

# sshd-toggle-password - Quickly enable/disable SSH password authentication on this host
# Usage: sshd-toggle-password
# For a single-line version that doesn't need the plugin loaded (e.g. to run
# once on a box you've just SSHed into), see sshd-toggle-password.sh.
sshd-toggle-password() {
    local sshd_config="/etc/ssh/sshd_config"
    local current

    current=$(sudo sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2}')
    if [ -z "$current" ]; then
        echo "Error: could not determine current PasswordAuthentication setting" >&2
        return 1
    fi

    local new_value="yes"
    [ "$current" = "yes" ] && new_value="no"

    if sudo grep -qiE '^[[:space:]]*PasswordAuthentication[[:space:]]+' "$sshd_config"; then
        sudo sed -i -E "s/^[[:space:]]*PasswordAuthentication[[:space:]]+.*/PasswordAuthentication ${new_value}/I" "$sshd_config"
    else
        echo "PasswordAuthentication ${new_value}" | sudo tee -a "$sshd_config" >/dev/null
    fi

    if command -v systemctl &>/dev/null; then
        sudo systemctl reload sshd 2>/dev/null || sudo systemctl reload ssh 2>/dev/null
    else
        sudo service sshd reload 2>/dev/null || sudo service ssh reload 2>/dev/null
    fi

    echo "SSH password authentication is now: ${new_value}"
}

# Completion function for ssh-gh commands
_ssh_git_operations_completion() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    if [ $COMP_CWORD -eq 1 ]; then
        # Complete first argument (ssh host)
        COMPREPLY=($(compgen -W "$(grep -h '^Host ' ~/.ssh/config 2>/dev/null | awk '{print $2}')" -- "$cur"))
    elif [ $COMP_CWORD -eq 2 ]; then
        # Complete second argument (repository path) - would need to query remote
        COMPREPLY=($(compgen -W "~/" -- "$cur"))
    fi
}

# Register completions for bash (if using bash-completion)
if [ -n "$BASH_VERSION" ]; then
    complete -F _ssh_git_operations_completion ssh-gh-remote-push
    complete -F _ssh_git_operations_completion ssh-gh-remote-pull
    complete -F _ssh_git_operations_completion ssh-gh-remote-fetch
    complete -F _ssh_git_operations_completion ssh-gh-remote-clone
    complete -F _ssh_git_operations_completion ssh-gh-remote-submodule-update
    complete -F _ssh_git_operations_completion ssh-gh-remote-commit
fi
