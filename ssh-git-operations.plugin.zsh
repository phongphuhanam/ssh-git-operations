#!/usr/bin/env zsh
# ssh-git-operations.plugin.zsh
# Oh My Zsh plugin for secure git push/pull/fetch over SSH with GitHub token authentication

# Verify gh CLI is available
if ! command -v gh &> /dev/null; then
    echo "Warning: GitHub CLI (gh) not found. ssh-git-operations requires 'gh' to be installed."
    echo "Install it from: https://github.com/cli/cli"
    return 1
fi

# Export functions for Oh My Zsh and completion
export -f ssh-gh-remote-push
export -f ssh-gh-remote-pull
export -f ssh-gh-remote-fetch
export -f scp-git-aware

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

# Run a git operation (push/pull/fetch) on the remote host.
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
_ssh_git_remote_run() {
    local ssh_host=$1
    local repo_path=$2
    local operation=$3
    local token=$4

    case "$operation" in
        push|pull)
            ssh "$ssh_host" bash -s <<REMOTE_EOF
set -e
cd "${repo_path}" || { echo "Error: could not access ${repo_path} on ${ssh_host}" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Error: ${repo_path} is not a git repository" >&2; exit 1; }
branch=\$(git rev-parse --abbrev-ref HEAD)
git -c credential.helper= -c credential.helper='!f() { echo "username=x-access-token"; echo "password=${token}"; }; f' ${operation} origin "\$branch"
REMOTE_EOF
            ;;
        fetch)
            ssh "$ssh_host" bash -s <<REMOTE_EOF
set -e
cd "${repo_path}" || { echo "Error: could not access ${repo_path} on ${ssh_host}" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Error: ${repo_path} is not a git repository" >&2; exit 1; }
git -c credential.helper= -c credential.helper='!f() { echo "username=x-access-token"; echo "password=${token}"; }; f' fetch origin
REMOTE_EOF
            ;;
        *)
            echo "Usage: _ssh_git_remote_run <user@host> <repo_path> <push|pull|fetch> <token>" >&2
            return 1
            ;;
    esac
}

# ssh-gh-remote-push - Push current branch to GitHub over SSH
# Usage: ssh-gh-remote-push user@host:/path  (scp-style with colon)
#        ssh-gh-remote-push user@host /path   (space-separated)
ssh-gh-remote-push() {
    local ssh_host=$1
    local repo_path=$2

    if [ -z "$ssh_host" ]; then
        echo "Usage: ssh-gh-remote-push <user@host>:[/path] or <user@host> [/path]" >&2
        echo "Examples:" >&2
        echo "  ssh-gh-remote-push dev@server.com:/home/user/myproject" >&2
        echo "  ssh-gh-remote-push dev@server.com /home/user/myproject" >&2
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
    _ssh_git_remote_run "$ssh_host" "$repo_path" push "$token"
}

# ssh-gh-remote-pull - Pull from GitHub over SSH
# Usage: ssh-gh-remote-pull user@host:/path  (scp-style with colon)
#        ssh-gh-remote-pull user@host /path   (space-separated)
ssh-gh-remote-pull() {
    local ssh_host=$1
    local repo_path=$2

    if [ -z "$ssh_host" ]; then
        echo "Usage: ssh-gh-remote-pull <user@host>:[/path] or <user@host> [/path]" >&2
        echo "Examples:" >&2
        echo "  ssh-gh-remote-pull dev@server.com:/home/user/myproject" >&2
        echo "  ssh-gh-remote-pull dev@server.com /home/user/myproject" >&2
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
    _ssh_git_remote_run "$ssh_host" "$repo_path" pull "$token"
}

# ssh-gh-remote-fetch - Fetch from GitHub over SSH
# Usage: ssh-gh-remote-fetch user@host:/path  (scp-style with colon)
#        ssh-gh-remote-fetch user@host /path   (space-separated)
ssh-gh-remote-fetch() {
    local ssh_host=$1
    local repo_path=$2

    if [ -z "$ssh_host" ]; then
        echo "Usage: ssh-gh-remote-fetch <user@host>:[/path] or <user@host> [/path]" >&2
        echo "Examples:" >&2
        echo "  ssh-gh-remote-fetch dev@server.com:/home/user/myproject" >&2
        echo "  ssh-gh-remote-fetch dev@server.com /home/user/myproject" >&2
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
    _ssh_git_remote_run "$ssh_host" "$repo_path" fetch "$token"
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
fi
