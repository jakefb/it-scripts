#!/bin/bash

set -u

if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

HOMEBREW_USERNAME="homebrew"
HOMEBREW_PATH="/opt/homebrew"
HOMEBREW_SCRIPT="/usr/local/bin/brew"

if [ -d "$HOMEBREW_PATH" ]; then
	HOMEBREW_DIR_OWNER=$(stat -f '%Su' "$HOMEBREW_PATH")

  if [ "$HOMEBREW_DIR_OWNER" == "$HOMEBREW_USERNAME" ]; then
    echo "$HOMEBREW_PATH is owned by $HOMEBREW_USERNAME. This means that homebrew was previously installed as a dedicated user. Homebrew will now be uninstalled..."
    rm -rf "$HOMEBREW_PATH"
    echo "Deleted $HOMEBREW_PATH."
 	else
    echo "$HOMEBREW_PATH exists but is owned by $HOMEBREW_DIR_OWNER. This indicates that homebrew was installed by the user."
  fi
else
  echo "$HOMEBREW_PATH does not exist. This indicates that homebrew is not installed."
fi

if id "$HOMEBREW_USERNAME" &>/dev/null; then
  sysadminctl -deleteUser "$HOMEBREW_USERNAME" -secure
  echo "Deleted the $HOMEBREW_USERNAME user."
else
  echo "User $HOMEBREW_USERNAME does not exist."
fi

if [ -f "$HOMEBREW_SCRIPT" ]; then
  rm "$HOMEBREW_SCRIPT"
  echo "Deleted $HOMEBREW_SCRIPT."
else
  echo "$HOMEBREW_SCRIPT does not exist."
fi

TEMP_FILE="/tmp/sudoers.tmp"

if grep -E "^${HOMEBREW_USERNAME}[ ]+ALL = \(ALL\) NOPASSWD:ALL$" /etc/sudoers; then
  echo "Removing the line for the homebrew user from the sudoers file."

  if ! visudo -c -f /etc/sudoers; then
    echo "Syntax error detected in /etc/sudoers (before making any changes). Aborting."
    exit 1
  fi

  sed "/^${HOMEBREW_USERNAME} ALL = (ALL) NOPASSWD:ALL$/d" /etc/sudoers > "$TEMP_FILE"

  if ! visudo -c -f "$TEMP_FILE"; then
    echo "Syntax error detected in the modified sudoers tmp file. Deleting $TEMP_FILE. Aborting."
    rm "$TEMP_FILE"
    exit 1
  fi

  mv "$TEMP_FILE" /etc/sudoers
  echo "The line was successfully removed from /etc/sudoers."
else
  echo "The line '$HOMEBREW_USERNAME ALL = (ALL) NOPASSWD:ALL' does not exist in /etc/sudoers."
fi
