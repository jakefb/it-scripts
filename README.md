# it-scripts

A collection of useful utility scripts for IT Support and scripts to deploy to Macs via JAMF. Please use these scripts at your own risk as they may contain bugs. PRs and issues are welcome.

## Mac rsync backup script

This script is intended for backing up a Mac user's home folder to an external drive. It comes with some built-in exclusions for all hidden files/folders except .git, and directories commonly containing personal data. The script will prompt you to confirm if you want to use these exclusions. The script has not been tested on Linux, but could be easily adapted to work on Unix systems other than Mac.

### Usage

**Things to note**

1. When using the built-in exclusions to exclude all hidden files/folders except .git, the script will not back up data within hidden folders. Some storage providers, such as OneDrive, may store files within hidden folders. Ensure that you either configure the exclusions as needed, or back up important data within hidden folders seperately.
1. Ensure that all data that you wish to exclude from the backup will be excluded by the built-in exclusions and/or an exclude file passed to the script as an argument.
1. If working with sensitive data, it is recommended that if backing up to an external drive, that you encrypted it with FileVault.
1. Ensure the Mac is connected to a charger. The script uses `caffeinate` to prevent the machine from sleeping until the script finishes running.
1. The script does not follow symbolic links.
1. If you wish to backup to a remote machine, use the syntax `user@remote:/remote/path` for the destination argument, and ensure rsync is installed at `/opt/homebrew/bin/rsync` on the remote machine. The script currently doesn't support backing up from a remote machine to a local machine.

**Running the backup script**

Run with:

sh```
./backups/rsync_backup.sh [source path] [destination path] [optional: exclude file]
```

## Script for installing homebrew as dedicated user

This script is intended for installing homebrew as a dedicated user, as a workaround for issues that arise when homebrew is installed on multi-user systems. The script was inspired by the following article: https://www.codejam.info/2021/11/homebrew-multi-user.html.

### Usage

**Things to note**

1. The installation script will create a `homebrew` admin/sudo user, with no password (and hidden from the login screen) but with all forms of authentication disabled, by setting the `AuthenticationAuthority` attribute to an empty string with `dscl`. This appears to disable all forms of authentications, while still being possible to switch to the user with `sudo su`. However, I cannot guarantee the robustness of this approach. In addition or instead of this, you could set the password to a random string with `dscl . -passwd "/Users/homebrew" "$(openssl rand -base64 32)"`, but I decided that disabling authentication via the `AuthenticationAuthority` attribute should be sufficient.
1. The installation script will add `homebrew ALL = (ALL) NOPASSWD:ALL` to the sudoers file, allowing the `homebrew` user to execute commands as sudo without needing to authenticate, for instances when `brew` requires elevated privileges. Note that this approach may have security implications worth considering.
1. The installation script will install homebrew to `/opt/homebrew` as the `homebrew` user. The `homebrew` user will be the owner of this directory.
1. The installation script modifies the permissions of `/opt/homebrew/bin/brew` so it can only be executed by the user `homebrew`, as a step to enforce users not to run `brew` as users other than the `homebrew` user.
1. The installation script creates a bash script that functions as brew, ensuring that on the first run, the user's shell profile is updated and that the Homebrew brew binary is executed as the homebrew user on every run. This script is placed at /usr/local/bin/brew, and because /usr/local/bin is part of users' PATHs by default, typing brew triggers this script. On the first run, the script updates the user's shell profile by adding the bin and sbin directories within /opt/homebrew to the PATH and aliasing brew to /usr/local/bin/brew, which is the script. This alias ensures that the script runs instead of the Homebrew brew binary, which would otherwise have precedence due to the updated PATH.

**Running the installer script**

Either deploy the script to JAMF, or run the script as root:

sh```
./jamf/install_homebrew_as_dedicated_user
```

**Running the uninstaller script**

Either deploy the script to JAMF, or run the script as root:

sh```
./jamf/uninstall_homebrew_as_dedicated_user
```
