# ssh-git-operations Examples

## Common Workflows

### 1. Quick Update on Remote Server

Pull the latest code from GitHub to a remote server:

```bash
# From your local machine
ssh-gh-remote-pull user@server.com /home/user/myapp

# What it does:
# 1. Connects to server
# 2. Detects current branch (e.g., main)
# 3. Pulls latest changes from origin/main using your local GitHub token
# 4. Token never stored on server
```

### 2. Push Changes from Remote to GitHub

Push work done on a remote machine back to GitHub:

```bash
# From your local machine
ssh-gh-remote-push deploy@worker.com /opt/workspace/project

# What it does:
# 1. Connects to worker machine
# 2. Detects current branch (e.g., feature/xyz)
# 3. Pushes to GitHub using your local token
# 4. Token never stored on worker
```

### 3. Check Available Repositories on Remote

Find all git repositories on a remote machine:

```bash
scp-git-aware user@server.com

# Output example:
# /home/user/project1
# /home/user/project2
# /opt/apps/service-a
# /opt/apps/service-b
```

### 4. Fetch Without Merge (Safe)

Update remote tracking branches without merging:

```bash
# Recommended approach for automated scripts
ssh-gh-remote-fetch prod@server.com /var/www/app

# What it does:
# 1. Fetches origin/branch info
# 2. Doesn't modify working directory
# 3. Allows you to inspect changes before merging
```

### 5. Clone a Repository on a Remote

Get a fresh copy of a GitHub repository onto a remote machine (provisioning, new checkout, recovery):

```bash
# From your local machine
ssh-gh-remote-clone dev@server.com owner/my-project

# What it does:
# 1. Connects to the server
# 2. Runs `git clone https://github.com/owner/my-project.git my-project` over the SSH session
# 3. Auth uses your local token, injected via a temporary credential helper
# 4. Token never stored on server

# With an explicit destination folder:
ssh-gh-remote-clone dev@server.com owner/my-project /opt/projects

# scp-style colon syntax:
ssh-gh-remote-clone dev@server.com:owner/my-project
```

## CI/CD Integration Examples

### GitHub Actions Workflow

Trigger operations on remote servers from GitHub Actions:

```yaml
name: Deploy to Remote

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup GitHub CLI
        run: |
          sudo apt-get update
          sudo apt-get install -y gh
          
      - name: Login to GitHub
        run: gh auth login --with-token < <(echo ${{ secrets.GITHUB_TOKEN }})
        
      - name: Pull latest on remote
        run: |
          # Add your SSH key
          mkdir -p ~/.ssh
          echo "${{ secrets.DEPLOY_SSH_KEY }}" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
          
          # Install the plugin
          git clone https://github.com/yourusername/ssh-git-operations ~/ssh-git-ops
          source ~/ssh-git-ops/ssh-git-operations.plugin.zsh
          
          # Trigger update on remote
          ssh-gh-remote-pull deploy@prod.server.com /var/www/app
```

### Cron Job on Local Machine

Periodically sync remote repositories with GitHub:

```bash
#!/bin/bash
# /usr/local/bin/sync-remote-repos.sh

# Source oh-my-zsh and the plugin
export ZSH="$HOME/.oh-my-zsh"
source "$ZSH/oh-my-zsh.sh"
source "$ZSH/custom/plugins/ssh-git-operations/ssh-git-operations.plugin.zsh"

# Sync all production servers
for server in prod1.com prod2.com prod3.com; do
    echo "Syncing $server..."
    ssh-gh-remote-fetch deploy@$server /var/www/app \
        && echo "✓ $server synced" \
        || echo "✗ $server failed"
done
```

Add to crontab:
```bash
crontab -e

# Run every hour
0 * * * * /usr/local/bin/sync-remote-repos.sh >> /var/log/remote-sync.log 2>&1
```

## Advanced Scenarios

### 1. Multi-Server Deployment

Deploy to multiple servers in sequence:

```bash
#!/bin/bash
SERVERS=("deploy@web1.com" "deploy@web2.com" "deploy@web3.com")

for server in "${SERVERS[@]}"; do
    echo "Updating $server..."
    if ssh-gh-remote-pull "$server" "/var/www/app"; then
        ssh "$server" "cd /var/www/app && ./deploy.sh"
        echo "✓ $server updated successfully"
    else
        echo "✗ Failed to update $server"
        exit 1
    fi
done
```

### 2. Conditional Pull Based on Branch

Only pull if on specific branch:

```bash
#!/bin/bash
server="deploy@app.server.com"
repo_path="/home/app/project"

# Check current branch on remote
current_branch=$(ssh "$server" "cd $repo_path && git rev-parse --abbrev-ref HEAD")

if [ "$current_branch" = "main" ]; then
    echo "On main branch, pulling updates..."
    ssh-gh-remote-pull "$server" "$repo_path"
else
    echo "On $current_branch branch, skipping auto-pull"
fi
```

### 3. Push, Verify, and Notify

Push to GitHub and verify on remote:

```bash
#!/bin/bash
server="dev@server.com"
repo_path="/home/dev/workspace"

echo "Pushing to GitHub..."
if ssh-gh-remote-push "$server" "$repo_path"; then
    echo "✓ Push successful"
    
    # Show what was pushed
    ssh "$server" "cd $repo_path && git log origin/HEAD -1 --oneline"
    
    # Send notification
    notify-send "Git push successful"
else
    echo "✗ Push failed"
    notify-send "Git push failed" "Check logs"
    exit 1
fi
```

### 4. Backup Repository to GitHub

Force push local work to GitHub (use with caution):

```bash
#!/bin/bash
server="backup@storage.com"
repo_path="/data/backup/repo"

# Fetch first to ensure remote is up to date
ssh-gh-remote-fetch "$server" "$repo_path"

# Then push with force flag
# Note: You may need to modify the plugin to support --force-with-lease
ssh "$server" "cd $repo_path && \
    git -c credential.helper='!f() { echo \"username=x-access-token\"; echo \"password=\$(gh auth token)\"; }; f' \
    push origin $(git rev-parse --abbrev-ref HEAD) --force-with-lease"
```

## Security Best Practices

### 1. Use Limited Scope Tokens

Create a GitHub Personal Access Token with limited scopes:

```bash
# In GitHub Settings > Developer settings > Personal access tokens
# Create token with only:
# - repo:status (read)
# - repo_deployment (read/write)
# - public_repo (read/write)
```

### 2. Monitor Token Usage

```bash
# Check when token was last used
gh auth status

# Check your token's scopes
gh api user/installations/self/access_tokens | jq '.scopes'
```

### 3. Rotate Tokens Regularly

```bash
# Set a calendar reminder to rotate tokens monthly
# When rotating:
# 1. Create new token in GitHub
# 2. Login locally: gh auth logout && gh auth login
# 3. Verify: gh auth status
```

### 4. Audit Remote Access

After pushing/pulling, audit what was changed:

```bash
# On remote machine
ssh user@server "cd /repo && git log --oneline -5"

# Verify remote tracking branches
ssh user@server "cd /repo && git branch -r"
```

## Troubleshooting Examples

### Problem: "fatal: repository not found"

**Cause**: Remote URL might be SSH instead of HTTPS

**Solution**:
```bash
ssh user@server "cd /repo && git remote -v"
# If shows git@github.com:user/repo.git, convert to HTTPS:
ssh user@server "cd /repo && git remote set-url origin https://github.com/user/repo.git"
```

### Problem: Branch doesn't match between local and remote

**Cause**: Working on different branches

**Solution**:
```bash
# Check local branch
ssh user@server "cd /repo && git status"

# Then use explicit operations on known branches
# or ensure you're on the same branch before operations
```

### Problem: Connection timeout

**Cause**: SSH connection too slow or network issues

**Solution**:
```bash
# Test SSH connection first
ssh -v user@server "pwd"

# Add to ~/.ssh/config for faster connections
Host server
    HostName server.com
    User user
    ControlMaster auto
    ControlPath ~/.ssh/control-%h-%p-%r
    ControlPersist 600
```
