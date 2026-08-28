# ssh-git-operations

A secure Oh My Zsh plugin for authenticated git push/pull/fetch operations over SSH to remote machines using GitHub token authentication. **Tokens are never persisted on remote machines.**

## Features

- **Secure token handling**: GitHub token is obtained locally and passed via git credential helper without storing it remotely
- **Three git operations**: `ssh-gh-remote-push`, `ssh-gh-remote-pull`, `ssh-gh-remote-fetch`
- **Current branch detection**: Automatically detects and operates on the current branch
- **Git-aware scp**: Helper command to discover git repositories on remote machines
- **No token persistence**: Token exists only in memory during the git operation
- **Tab completion**: Full autocompletion support for commands and SSH hosts from ~/.ssh/config

## Prerequisites

- **Oh My Zsh** - [Installation guide](https://ohmyz.sh/#install)
- **GitHub CLI (gh)** - [Installation guide](https://github.com/cli/cli#installation)
- **Git** - Available on both local and remote machines
- **SSH access** - Configured SSH keys for password-less authentication

### Verify Prerequisites

```bash
# Check if you have gh CLI installed and authenticated
gh auth status

# Ensure SSH access is configured
ssh your-host "git --version"
```

## Installation

### Option 1: Oh My Zsh Plugin Manager

Clone this repository into your Oh My Zsh custom plugins directory:

```bash
git clone https://github.com/yourusername/ssh-git-operations \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/ssh-git-operations
```

Add the plugin to your `.zshrc`:

```zsh
plugins=(... ssh-git-operations)
```

Reload your shell:

```bash
source ~/.zshrc
```

### Option 2: Manual Installation

1. Download the plugin file to a location of your choice
2. Source it in your `.zshrc`:

```bash
source /path/to/ssh-git-operations.plugin.zsh
```

## Usage

### Push Current Branch to GitHub

Push the current branch from a remote machine to GitHub:

```bash
ssh-gh-remote-push user@remote-server.com /path/to/repository
```

**Example:**
```bash
ssh-gh-remote-push dev@myserver.com /home/user/my-project
```

### Pull from GitHub

Pull the current branch from GitHub to a remote machine:

```bash
ssh-gh-remote-pull user@remote-server.com /path/to/repository
```

**Example:**
```bash
ssh-gh-remote-pull dev@myserver.com /home/user/my-project
```

### Fetch from GitHub (Recommended)

Fetch updates from GitHub without merging (safer than pull):

```bash
ssh-gh-remote-fetch user@remote-server.com /path/to/repository
```

**Example:**
```bash
ssh-gh-remote-fetch dev@myserver.com /home/user/my-project
```

### Discover Git Repositories on Remote Machine

Find git repositories on a remote machine for easy reference:

```bash
scp-git-aware user@remote-server.com
```

This will scan for `.git` directories and display the paths to git repositories on the remote machine.

## How It Works

1. **Local token extraction**: The plugin retrieves your GitHub token locally using `gh auth token` — this always runs on your machine, never on the remote host.
2. **Script delivered over stdin**: The whole remote-side script (cd, branch detection, the git command) is piped to `ssh <host> bash -s` over the SSH session's stdin, instead of being passed as a single `ssh host "<command>"` argument. This keeps the token out of the argv of the `ssh` process (visible locally via `ps`) and the `bash -s` process (visible remotely via `ps`).
3. **Remote branch detection**: The script detects the current branch on the remote repository itself, in the same SSH round trip.
4. **Reset-then-set credential helper**: The git command runs as `git -c credential.helper= -c credential.helper='!f() {...}; f' <push|pull|fetch> ...`. The leading `-c credential.helper=` clears any helper chain accumulated from config files *for this invocation only* (verified by testing directly against `git credential fill`/`approve`), so a pre-existing `credential.helper` on the remote (e.g. `store`, `osxkeychain`, a credential manager) is never consulted and never gets a chance to cache the token to disk.
5. **Nothing written by this plugin**: We never write to `.git/config`, `~/.gitconfig`, or `.git-credentials` on the remote machine.

### Security Details

```bash
# Sent to `ssh <host> bash -s` over stdin (not as a command-line argument):
set -e
cd "<repo_path>" || { echo "..." >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "..." >&2; exit 1; }
branch=$(git rev-parse --abbrev-ref HEAD)
git -c credential.helper= -c credential.helper='!f() { echo "username=x-access-token"; echo "password=$TOKEN"; }; f' push origin "$branch"
```

- Token is obtained from your local machine's GitHub CLI authentication and never leaves memory on your side except as part of the script text piped to `ssh`.
- The script (token included) travels only inside the encrypted SSH channel, via stdin — not as a process argument.
- The credential-helper chain is reset before ours is added, so a pre-existing remote helper cannot also persist the token.
- Git never stores credentials in `.git/config`, `~/.gitconfig`, or `.gitcredentials` on the remote machine as a result of this plugin.
- Each operation fetches a fresh token from your local `gh` CLI — nothing is cached or reused across invocations.

### What this does *not* eliminate

- Once `git` actually runs on the remote host, the token is still part of the `git -c credential.helper=...` argument for that process. For the few seconds the command executes, `ps auxww` on the remote host (run by root, or another user permitted to read process listings) could see it in the `git` process's own argv. Moving the script to stdin removes the token from the `ssh`/`bash -s` processes, but not from `git`'s own command-line arguments — avoiding that fully would require passing the token through a file descriptor or named pipe instead of a `-c` value.
- On a hardened remote host with command-line auditing enabled (`auditd` execve logging, a `ForceCommand` wrapper, session recording), the token could still end up in those logs, since they capture process argv independently of git or our script.
- We don't write to the remote's shell history (this is a non-interactive `ssh` exec, not an interactive login shell), but that's a property of how the remote is configured, not something this plugin can guarantee.

## Prerequisites for Remote Repositories

Your remote repository must be configured with HTTPS remote URLs for this to work:

```bash
# Check current remote configuration
ssh user@host "cd /path/to/repo && git remote -v"

# If using SSH, you may need to convert to HTTPS
ssh user@host "cd /path/to/repo && git remote set-url origin https://github.com/user/repo.git"
```

## Troubleshooting

### "gh: command not found"

Ensure GitHub CLI is installed on your **local machine**:
```bash
# macOS with Homebrew
brew install gh

# Linux (Ubuntu/Debian)
sudo apt-get install gh

# Or see: https://github.com/cli/cli#installation
```

### "Failed to retrieve GitHub token"

Authenticate with GitHub CLI:
```bash
gh auth login
# Follow the prompts to authenticate
```

### "Could not determine current branch on remote machine"

Verify the repository path is correct:
```bash
ssh user@host "cd /path/to/repo && git status"
```

### "Permission denied (publickey)"

Ensure SSH keys are properly configured:
```bash
# Test SSH connection
ssh -v user@host "echo 'SSH works'"

# Add SSH key to agent if needed
ssh-add ~/.ssh/id_rsa
```

### Push/Pull fails with authentication error

Ensure the remote repository uses HTTPS URLs:
```bash
ssh user@host "cd /path/to/repo && git remote -v"
# Should show: origin https://github.com/user/repo.git
```

If using SSH URLs, convert to HTTPS:
```bash
ssh user@host "cd /path/to/repo && git remote set-url origin https://github.com/user/repo.git"
```

## Integration with CI/CD

This plugin is useful for remote machines that don't have GitHub SSH keys configured but need to push/pull code:

```bash
#!/bin/bash
# Example deployment script
ssh-gh-remote-pull deploy@production.server /var/www/app
ssh-gh-remote-fetch deploy@staging.server /var/www/staging
```

## Security Considerations

- **Token scope**: Use a GitHub Personal Access Token with limited scopes if possible
- **SSH security**: Ensure SSH connections to remote machines are properly secured
- **Token rotation**: Rotate your GitHub token regularly
- **Network**: Only use on trusted networks; token is passed over SSH (encrypted)

## License

MIT License - See LICENSE file for details

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues.

## Related Projects

- [GitHub CLI](https://github.com/cli/cli)
- [Oh My Zsh](https://ohmyz.sh)
- [Git Credential Helper](https://git-scm.com/book/en/v2/Git-Tools-Credential-Storage)
