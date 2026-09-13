#!/bin/bash
# Toggle SSH password authentication (PasswordAuthentication yes/no) on this
# machine and reload sshd. Self-contained - no need to have the
# ssh-git-operations plugin loaded, so this is meant to be run as a single
# line, e.g. right after logging into a box you want to flip it on/off:
#
#   curl -fsSL https://raw.githubusercontent.com/phongphuhanam/ssh-git-operations/main/sshd-toggle-password.sh | bash
#   wget -qO- https://raw.githubusercontent.com/phongphuhanam/ssh-git-operations/main/sshd-toggle-password.sh | bash
#
# It can also be run against a remote host in one line from your own
# machine, by piping it into `ssh` instead of `bash` (requires the remote
# account to have passwordless sudo for sed/systemctl, since there's no tty
# for sudo to prompt through over a non-interactive ssh pipe):
#
#   curl -fsSL https://raw.githubusercontent.com/phongphuhanam/ssh-git-operations/main/sshd-toggle-password.sh | ssh user@host bash

SSHD_CONFIG="/etc/ssh/sshd_config"

current=$(sudo sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2}')
if [ -z "$current" ]; then
    echo "Error: could not determine current PasswordAuthentication setting" >&2
    exit 1
fi

new_value="yes"
[ "$current" = "yes" ] && new_value="no"

if sudo grep -qiE '^[[:space:]]*PasswordAuthentication[[:space:]]+' "$SSHD_CONFIG"; then
    sudo sed -i -E "s/^[[:space:]]*PasswordAuthentication[[:space:]]+.*/PasswordAuthentication ${new_value}/I" "$SSHD_CONFIG"
else
    echo "PasswordAuthentication ${new_value}" | sudo tee -a "$SSHD_CONFIG" >/dev/null
fi

if command -v systemctl &>/dev/null; then
    sudo systemctl reload sshd 2>/dev/null || sudo systemctl reload ssh 2>/dev/null
else
    sudo service sshd reload 2>/dev/null || sudo service ssh reload 2>/dev/null
fi

echo "SSH password authentication is now: ${new_value}"
