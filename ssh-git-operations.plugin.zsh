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

# Helper function to find and select git repo interactively
_ssh_git_select_repo() {
    local ssh_host=$1
    local search_path=${2:-~/}

    if ! command -v fzf &> /dev/null; then
        echo "Error: fzf is not installed. Install it for interactive directory selection." >&2
        echo "  macOS: brew install fzf" >&2
        echo "  Linux: sudo apt-get install fzf" >&2
        return 1
    fi

    echo "Scanning for git repositories on $ssh_host (this may take a moment)..."
    local repos=$(ssh "$ssh_host" "find $search_path -maxdepth 3 -type d -name '.git' 2>/dev/null | sed 's|/.git||' | sort" 2>/dev/null)

    if [ -z "$repos" ]; then
        echo "Error: No git repositories found on $ssh_host under $search_path" >&2
        return 1
    fi

    local selected=$(echo "$repos" | fzf --preview "ssh $ssh_host 'cd {} && git log --oneline -3 2>/dev/null'" \
                                       --preview-window=right:40% \
                                       --header "Select a git repository (preview shows last 3 commits)")

    if [ -z "$selected" ]; then
        echo "No repository selected" >&2
        return 1
    fi

    echo "$selected"
}

# Helper function to execute git command over SSH with token authentication
_ssh_git_exec() {
    local ssh_host=$1
    local git_command=$2
    local remote_branch=$3

    if [ -z "$ssh_host" ] || [ -z "$git_command" ]; then
        echo "Usage: _ssh_git_exec <user@host> <push|pull|fetch> [branch]" >&2
        return 1
    fi

    # Get current branch if not specified
    if [ -z "$remote_branch" ]; then
        remote_branch=$(ssh "$ssh_host" 'cd "$1" && git rev-parse --abbrev-ref HEAD' _ 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "Error: Could not determine current branch on remote machine" >&2
            return 1
        fi
    fi

    # Get token from local machine
    local token
    token=$(_ssh_git_get_token)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Build git command with credential helper
    local git_cmd="git -c credential.helper='!f() { echo \"username=x-access-token\"; echo \"password=$token\"; }; f' $git_command"

    if [ "$git_command" = "push" ] || [ "$git_command" = "pull" ]; then
        git_cmd="$git_cmd origin $remote_branch"
    fi

    # Execute on remote machine
    ssh "$ssh_host" "cd \"\$1\" && eval \"$git_cmd\"" _
}

# ssh-gh-remote-push - Push current branch to GitHub over SSH
# Usage: ssh-gh-remote-push user@host [path_to_repo]
#        ssh-gh-remote-push user@host (interactive if path omitted)
ssh-gh-remote-push() {
    local ssh_host=$1
    local repo_path=$2

    if [ -z "$ssh_host" ]; then
        echo "Usage: ssh-gh-remote-push <user@host> [repo_path]" >&2
        echo "Example: ssh-gh-remote-push dev@server.com /home/user/myproject" >&2
        return 1
    fi

    # If no path provided, use interactive selection
    if [ -z "$repo_path" ]; then
        echo "No repository path specified. Opening interactive selector..."
        repo_path=$(_ssh_git_select_repo "$ssh_host" "~/")
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi

    echo "Pushing to GitHub via SSH..."
    ssh "$ssh_host" "cd \"$repo_path\" && git rev-parse --abbrev-ref HEAD" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Could not access git repository at $repo_path on $ssh_host" >&2
        return 1
    fi

    # Get current branch on remote
    local branch=$(ssh "$ssh_host" "cd \"$repo_path\" && git rev-parse --abbrev-ref HEAD")
    local token
    token=$(_ssh_git_get_token)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Execute push with token
    ssh "$ssh_host" "cd \"$repo_path\" && git -c credential.helper='!f() { echo \"username=x-access-token\"; echo \"password=$token\"; }; f' push origin $branch"
}

# ssh-gh-remote-pull - Pull from GitHub over SSH
# Usage: ssh-gh-remote-pull user@host [path_to_repo]
#        ssh-gh-remote-pull user@host (interactive if path omitted)
ssh-gh-remote-pull() {
    local ssh_host=$1
    local repo_path=$2

    if [ -z "$ssh_host" ]; then
        echo "Usage: ssh-gh-remote-pull <user@host> [repo_path]" >&2
        echo "Example: ssh-gh-remote-pull dev@server.com /home/user/myproject" >&2
        return 1
    fi

    # If no path provided, use interactive selection
    if [ -z "$repo_path" ]; then
        echo "No repository path specified. Opening interactive selector..."
        repo_path=$(_ssh_git_select_repo "$ssh_host" "~/")
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi

    echo "Pulling from GitHub via SSH..."
    ssh "$ssh_host" "cd \"$repo_path\" && git rev-parse --abbrev-ref HEAD" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Could not access git repository at $repo_path on $ssh_host" >&2
        return 1
    fi

    # Get current branch on remote
    local branch=$(ssh "$ssh_host" "cd \"$repo_path\" && git rev-parse --abbrev-ref HEAD")
    local token
    token=$(_ssh_git_get_token)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Execute pull with token
    ssh "$ssh_host" "cd \"$repo_path\" && git -c credential.helper='!f() { echo \"username=x-access-token\"; echo \"password=$token\"; }; f' pull origin $branch"
}

# ssh-gh-remote-fetch - Fetch from GitHub over SSH
# Usage: ssh-gh-remote-fetch user@host [path_to_repo]
#        ssh-gh-remote-fetch user@host (interactive if path omitted)
ssh-gh-remote-fetch() {
    local ssh_host=$1
    local repo_path=$2

    if [ -z "$ssh_host" ]; then
        echo "Usage: ssh-gh-remote-fetch <user@host> [repo_path]" >&2
        echo "Example: ssh-gh-remote-fetch dev@server.com /home/user/myproject" >&2
        return 1
    fi

    # If no path provided, use interactive selection
    if [ -z "$repo_path" ]; then
        echo "No repository path specified. Opening interactive selector..."
        repo_path=$(_ssh_git_select_repo "$ssh_host" "~/")
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi

    echo "Fetching from GitHub via SSH..."
    ssh "$ssh_host" "cd \"$repo_path\" && git rev-parse --abbrev-ref HEAD" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Could not access git repository at $repo_path on $ssh_host" >&2
        return 1
    fi

    local token
    token=$(_ssh_git_get_token)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Execute fetch with token
    ssh "$ssh_host" "cd \"$repo_path\" && git -c credential.helper='!f() { echo \"username=x-access-token\"; echo \"password=$token\"; }; f' fetch origin"
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
