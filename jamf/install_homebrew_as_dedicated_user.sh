#!/bin/bash

set -u

VERSION="1"

if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

### BEGIN adapted code from https://github.com/Homebrew/install/blob/master/install.sh
# BSD 2-Clause License

# Copyright (c) 2009-present, Homebrew contributors
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:

# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.

# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
major_minor() {
  echo "${1%%.*}.$(
    X="${1#*.}"
    echo "${X%%.*}"
  )"
}

version_gt() {
  [[ "${1%.*}" -gt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -gt "${2#*.}" ]]
}
version_ge() {
  [[ "${1%.*}" -gt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -ge "${2#*.}" ]]
}
version_lt() {
  [[ "${1%.*}" -lt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -lt "${2#*.}" ]]
}

chomp() {
  printf "%s" "${1/"$'\n'"/}"
}

major_minor() {
  echo "${1%%.*}.$(
    X="${1#*.}"
    echo "${X%%.*}"
  )"
}

MACOS_VERSION="$(major_minor "$(/usr/bin/sw_vers -productVersion)")"

echo "macos version: $MACOS_VERSION"

if version_lt "$MACOS_VERSION" "10.7"; then
  echo "Your macOS version is too old."
  return 1
fi

should_install_command_line_tools() {
  if version_gt "$MACOS_VERSION" "10.13"; then
    ! [[ -e "/Library/Developer/CommandLineTools/usr/bin/git" ]]
  else
    ! [[ -e "/Library/Developer/CommandLineTools/usr/bin/git" ]] ||
      ! [[ -e "/usr/include/iconv.h" ]]
  fi
}

if should_install_command_line_tools && version_ge "${MACOS_VERSION}" "10.13"; then
  echo "Searching online for the Command Line Tools"
  # This temporary file prompts the 'softwareupdate' utility to list the Command Line Tools
  CLT_PLACEHOLDER="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  touch "$CLT_PLACEHOLDER"

  CLT_LABEL_COMMAND="/usr/sbin/softwareupdate -l |
                      grep -B 1 -E 'Command Line Tools' |
                      awk -F'*' '/^ *\\*/ {print \$2}' |
                      sed -e 's/^ *Label: //' -e 's/^ *//' |
                      sort -V |
                      tail -n1"
  CLT_LABEL="$(chomp "$(/bin/bash -c "$CLT_LABEL_COMMAND")")"

  if [[ -n "$CLT_LABEL" ]]; then
    echo "Installing $CLT_LABEL"
    /usr/sbin/softwareupdate -i "$CLT_LABEL"
    /usr/bin/xcode-select --switch /Library/Developer/CommandLineTools
  fi
  /bin/rm -f $CLT_PLACEHOLDER
fi
### END adapted code

HOMEBREW_USERNAME="homebrew"
HOMEBREW_PATH="/opt/homebrew"
HOMEBREW_SCRIPT="/usr/local/bin/brew"

if [ -d "$HOMEBREW_PATH" ]; then
	HOMEBREW_DIR_OWNER=$(stat -f '%Su' "$HOMEBREW_PATH")

  if [ "$HOMEBREW_DIR_OWNER" == "$HOMEBREW_USERNAME" ]; then
    echo "$HOMEBREW_PATH is owned by $HOMEBREW_USERNAME. This means it was previously installed correctly. Exiting."
    exit 0
 	else
    echo "$HOMEBREW_PATH exists but is owned by $HOMEBREW_DIR_OWNER. This indicates that homebrew was installed by the user. Exiting."
    exit 1
  fi
fi

if [ $? -eq 0 ]; then
  echo "Xcode command line tools were installed successfully."
else
  echo "Xcode command line tools installation failed."
  exit 1
fi

HOMEBREW_USERS_SHELL="zsh"
HOMEBREW_USERS_SHELL_PROFILE_FILENAME=".zprofile"

create_user_if_not_exists() {
  local USER_TO_CREATE="$1"
  if ! id "$USER_TO_CREATE" &>/dev/null; then
    echo "User $USER_TO_CREATE does not exist, creating."
    dscl . -create "/Users/$USER_TO_CREATE"
    dscl . -create "/Users/$USER_TO_CREATE" UserShell /bin/"$HOMEBREW_USERS_SHELL"
    dscl . -create "/Users/$USER_TO_CREATE" UniqueID "$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1 | awk '{print $1+1}')"
    dscl . -create "/Users/$USER_TO_CREATE" PrimaryGroupID 20
    dscl . -create "/Users/$USER_TO_CREATE" NFSHomeDirectory "/Users/$USER_TO_CREATE"
    # Set the AuthenticationAuthority to an empty string, which disables the user from logging in
    dscl . -create "/Users/$USER_TO_CREATE" AuthenticationAuthority ""
    dscl . -create "/Users/$USER_TO_CREATE" IsHidden 1
    createhomedir -c -u "$USER_TO_CREATE" > /dev/null
    dseditgroup -o edit -a "$USER_TO_CREATE" -t user admin
    echo "$HOMEBREW_USERNAME ALL = (ALL) NOPASSWD:ALL" | EDITOR='tee -a' visudo
    echo "User $USER_TO_CREATE created successfully and added to the admin group."
  else
    echo "User $USER_TO_CREATE already exists."
  fi
}

create_user_if_not_exists "$HOMEBREW_USERNAME"

git clone https://github.com/Homebrew/brew $HOMEBREW_PATH
chown "$HOMEBREW_USERNAME":admin $HOMEBREW_PATH
chown -R "$HOMEBREW_USERNAME":admin $HOMEBREW_PATH
chmod 700 $HOMEBREW_PATH/bin/brew
su - "$HOMEBREW_USERNAME" <<EOF
  "$HOMEBREW_PATH"/bin/brew update --force --quiet
  # Not sure why this is necessary but it was mentioned here: https://docs.brew.sh/Installation
  chmod -R go-w "$HOMEBREW_PATH/share/zsh"

  # Add a version number to the installation, can be used for patches later
  echo "$VERSION" >> "$HOMEBREW_PATH/_installer_version"

  if [ -n ~/"$HOMEBREW_USERS_SHELL_PROFILE_FILENAME" ]; then
 	  echo 'eval "$($HOMEBREW_PATH/bin/brew shellenv)"' >> ~/"$HOMEBREW_USERS_SHELL_PROFILE_FILENAME"
  fi
EOF

echo '#!/bin/bash
set -u

if [[ "$(whoami)" == "root" || "$(whoami)" == "homebrew" ]]; then
  echo "This script cannot be run as root or homebrew."
  exit 1
fi

HOMEBREW_PATH="'"$HOMEBREW_PATH"'"
HOMEBREW_SCRIPT="'"$HOMEBREW_SCRIPT"'"

TARGET_PATH="$HOMEBREW_PATH/bin:$HOMEBREW_PATH/sbin"

SHELL_NAME=$(basename "$SHELL")

if [[ "$SHELL_NAME" == "bash" ]]; then
  SHELL_PROFILE_PATH="$HOME/.bash_profile"
elif [[ "$SHELL_NAME" == "zsh" ]]; then
  SHELL_PROFILE_PATH="$HOME/.zprofile"
else
  echo "Unsupported shell. Please manually add the following lines to your shell profile:"
  echo "export PATH=\"$TARGET_PATH:\$PATH\""
  echo "alias brew=\"$HOMEBREW_SCRIPT\""
  exit 1
fi

if grep -q "export PATH=\"$TARGET_PATH:\$PATH\"" "$SHELL_PROFILE_PATH" && grep -q "alias brew=\"$HOMEBREW_SCRIPT\"" "$SHELL_PROFILE_PATH"; then
  PATH_AND_ALIAS_EXISTS="1"
else
  PATH_AND_ALIAS_EXISTS="0"
fi

if [[ "$PATH_AND_ALIAS_EXISTS" == "0" ]]; then
  echo "export PATH=\"$TARGET_PATH:\$PATH\"" >> "$SHELL_PROFILE_PATH"
  echo "Added \`export PATH=\"$TARGET_PATH:\$PATH\"\` to $SHELL_PROFILE_PATH"
  echo "alias brew=\"$HOMEBREW_SCRIPT\"" >> "$SHELL_PROFILE_PATH"
  echo "Added \`alias brew=\"$HOMEBREW_SCRIPT\"\` to $SHELL_PROFILE_PATH"
  echo "Please run the following command to source your shell profile:"
  echo "source $SHELL_PROFILE_PATH"
fi

sudo -Hu homebrew "$HOMEBREW_PATH"/bin/brew "$@"' > "$HOMEBREW_SCRIPT"
chmod +x /usr/local/bin/brew
