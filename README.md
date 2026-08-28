# ssh-git-operations

A secure Oh My Zsh plugin for authenticated git push/pull/fetch operations over SSH to remote machines using GitHub token authentication. **Tokens are never persisted on remote machines.**

## Features

- **Secure token handling**: GitHub token is obtained locally and passed via git credential helper without storing it remotely
- **Three git operations**: `ssh-gh-remote-push`, `ssh-gh-remote-pull`, `ssh-gh-remote-fetch`
- **Current branch detection**: Automatically detects and operates on the current branch
- **Git-aware scp**: Helper command to discover git repositories on remote machines
- **No token persistence**: Token exists only in memory during the git operation

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

1. **Local token extraction**: The plugin retrieves your GitHub token locally using `gh auth token`
2. **SSH connection**: Establishes SSH connection to the remote machine
3. **Remote branch detection**: Detects the current branch on the remote repository
4. **Temporary credential helper**: Passes the token via git's credential helper mechanism without storing it
5. **Token memory-only**: The token exists only in memory during the operation and is never saved to disk on the remote machine

### Security Details

```bash
# The credential helper is injected inline:
git -c credential.helper='!f() { echo "username=x-access-token"; echo "password=$TOKEN"; }; f' push origin current-branch
```

- Token is obtained from your local machine's GitHub CLI authentication
- Token is passed as an environment variable in the SSH session
- Git never stores credentials in `.git/config` or `.gitcredentials` on the remote machine
- Each operation fetches a fresh token from your local gh CLI

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
