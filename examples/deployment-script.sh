#!/bin/bash
# Example: Automated deployment script using ssh-git-operations
# This script updates code on remote servers and pushes any changes back to GitHub

set -e

PROD_SERVER="deploy@prod.example.com"
STAGING_SERVER="deploy@staging.example.com"
REPO_PATH="/var/www/app"

echo "=== Deployment Script with ssh-git-operations ==="

# Function to deploy to a server
deploy_to_server() {
    local server=$1
    local path=$2
    local env=$3

    echo ""
    echo "Deploying to $env ($server)..."

    # Fetch latest changes from GitHub
    echo "Fetching latest changes..."
    ssh-gh-remote-fetch "$server" "$path"

    # Show current branch and latest commits
    echo "Current status on $env:"
    ssh "$server" "cd $path && git log --oneline -3"

    echo "✓ $env deployment complete"
}

# Deploy to staging first
deploy_to_server "$STAGING_SERVER" "$REPO_PATH" "Staging"

# Ask for confirmation before prod
read -p "Deploy to production? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    deploy_to_server "$PROD_SERVER" "$REPO_PATH" "Production"
    echo ""
    echo "=== All deployments complete ==="
else
    echo "Production deployment cancelled"
    exit 1
fi
