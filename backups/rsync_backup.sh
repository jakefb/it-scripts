#!/bin/bash
set -eu
handle_exit() {
  local EXIT_CODE=$?
  if [ "$EXIT_CODE" -ne 0 ]; then
    echo $'\e[31mAn error occurred. Exiting...\e[0m'
  fi
  exit "$EXIT_CODE"
}
trap handle_exit EXIT
caffeinate -w $$ &
if [ "$EUID" -ne 0 ]; then
  read -p $'\e[34mIf you are copying another users home folder, it is recommended to run this script with sudo. Would you like to continue without sudo? (y/n) \e[0m' RUN_WITHOUT_SUDO
  if [ "$RUN_WITHOUT_SUDO" = "y" ]; then
    echo "Continuing without sudo."
  else
    echo "Exiting."
    exit 2
  fi
fi
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 [source path] [destination path] [optional: exclude file]"
  exit 2
fi
set +u
SOURCE_DIR="$1"
SOURCE_DIR_TRAILING_SLASH="${SOURCE_DIR%/}/"
DEST_DIR="$2"
EXCLUDE_FILE="$3"
set -u
function dest_exists_ask_to_continue() {
  read -p $'\e[34mDestination directory already exists; do you want to resume an interrupted rsync copy? (y/n) \e[0m' SHOULD_APPEND
  if [ "$SHOULD_APPEND" = "y" ]; then
    echo "Interrupted rsync copy will be resumed."
  else
    echo "Exiting."
    exit 2
  fi
}
NL="\\"$'\n'" "
DEST_DIR_NO_SLASH="${DEST_DIR%/}"
if [[ "$DEST_DIR" != *":"* ]]; then
  IS_REMOTE_COPY="0"
  RSYNC_DEST_BASED_ARG=""
  LOG_PATH="${DEST_DIR_NO_SLASH}_rsync_log.txt"
  if [ -d "$DEST_DIR" ]; then
    if [ "$(ls -A $DEST_DIR)" ]; then
      dest_exists_ask_to_continue
    fi
  fi
else
  IS_REMOTE_COPY="1"
  RSYNC_DEST_BASED_ARG="$NL --checksum $NL --compress $NL --rsync-path=\"/opt/homebrew/bin/rsync\""
  LOG_PATH="$(basename "$DEST_DIR_NO_SLASH")_rsync_log.txt"
  echo "You have specified a remote machine. Make sure rsync is installed at /opt/homebrew/bin/rsync on the remote machine."
  REMOTE_ADDRESS=$(echo "$DEST_DIR" | cut -d':' -f1)
  REMOTE_DIR=$(echo "$DEST_DIR" | cut -d':' -f2)
  ssh "$REMOTE_ADDRESS" "[ -d '$REMOTE_DIR' ]" && {
    dest_exists_ask_to_continue
  } || {
    EXIT_STATUS=$?
    if [ "$EXIT_STATUS" -eq 255 ]; then
      echo "SSH connection failed. Check your connection or SSH configuration."
      exit 1
    fi
  }
fi
RSYNC_COMMAND_BASE_PREFIX='rsync \
  --archive \
  --stats \
  --human-readable'
read -p $'\e[34mDo you want to view the built-in exclusions for all hidden files/folders except .git, and directories commonly containing personal data (you will then be prompted to confirm if you want to use them)? (y/n) \e[0m' VIEW_DEFAULT_EXCLUDES
if [ "$VIEW_DEFAULT_EXCLUDES" = "y" ]; then
  DEFAULT_EXCLUDES='--include=".git/" \
  --exclude=".*" \
  --exclude="node_modules/" \
  --exclude="/Library/" \
  --exclude="/Applications/" \
  --exclude="/Dropbox/" \
  --exclude="/Pictures/Photo Booth Library/" \
  --exclude="/Pictures/Photos Library.photoslibrary/" \
  --exclude="/Movies/iMovie Library.imovielibrary/" \
  --exclude="/Movies/iMovie Theater.theater/" \
  --exclude="/Music/Music/" \
  --exclude="/Movies/TV/" \
  --exclude="env/" \
  --exclude="venv/" \
  --exclude="/opt/" \
  --exclude="/OneDrive - *" \
  --exclude="/Applications (Parallels)/" \
  --exclude="/iCloud Drive (Archive)/"'
  echo "The built-in exclusions are:"
  echo "  $DEFAULT_EXCLUDES"
  read -p $'\e[34mDo you want to use the above flags? (y/n) \e[0m' ADD_DEFAULT_EXCLUDES
  if [ "$ADD_DEFAULT_EXCLUDES" = "y" ]; then
    RSYNC_COMMAND_BASE_PREFIX="$RSYNC_COMMAND_BASE_PREFIX $NL $DEFAULT_EXCLUDES"
  fi
fi
if [ -n "$EXCLUDE_FILE" ]; then
  RSYNC_COMMAND_BASE_PREFIX="$RSYNC_COMMAND_BASE_PREFIX $NL --exclude-from=\"$EXCLUDE_FILE\""
fi
RSYNC_COMMAND_BASE="$RSYNC_COMMAND_BASE_PREFIX $RSYNC_DEST_BASED_ARG"
RSYNC_COMMAND_SUFFIX="\"$SOURCE_DIR_TRAILING_SLASH\" \"$DEST_DIR\""
RSYNC_V2_COMMAND_DRY="$RSYNC_COMMAND_BASE $NL --verbose $NL $RSYNC_COMMAND_SUFFIX $NL --dry-run"
RSYNC_V2_COMMAND="$RSYNC_COMMAND_BASE $NL --verbose $NL --log-file=\"$LOG_PATH\" $NL $RSYNC_COMMAND_SUFFIX"
RSYNC_V3_COMMAND_DRY="$RSYNC_COMMAND_BASE $NL --verbose $NL --no-inc-recursive $NL $RSYNC_COMMAND_SUFFIX $NL --dry-run"
RSYNC_V3_COMMAND="$RSYNC_COMMAND_BASE $NL --no-inc-recursive $NL --info=progress2 $NL --info=name0 $NL --log-file=\"$LOG_PATH\" $NL $RSYNC_COMMAND_SUFFIX"
if [ "$(which rsync)" = "/opt/homebrew/bin/rsync" ]; then
  echo "rsync is installed at /opt/homebrew/bin/rsync"
  RSYNC_COMMAND_DRY="$RSYNC_V3_COMMAND_DRY"
  RSYNC_COMMAND="$RSYNC_V3_COMMAND"
elif [ "$(which pkgx)" = "/usr/local/bin/pkgx" ]; then
  echo "pkgx is installed, rsync will be run with pkgx"
  RSYNC_COMMAND_DRY="pkgx $RSYNC_V3_COMMAND_DRY"
  RSYNC_COMMAND="pkgx $RSYNC_V3_COMMAND"
else
  echo "rsync is not installed at /opt/homebrew/bin/rsync, using macOS built-in rsync"
  RSYNC_COMMAND_DRY="$RSYNC_V2_COMMAND_DRY"
  RSYNC_COMMAND="$RSYNC_V2_COMMAND"
fi
echo "Command: $RSYNC_COMMAND_DRY"
read -p $'\e[34mThe above rsync command will be run as a dry run. Do you want to continue? (y/n) \e[0m' EXECUTE_DRY_RUN
if [ "$EXECUTE_DRY_RUN" != "y" ]; then
  echo "Exiting."
  exit 2
fi
eval "$RSYNC_COMMAND_DRY"
echo $'\e[33mNote: the above is a dry run. Your files have not been copied yet.\e[0m'
read -p $'\e[34mDo you want to run the same rsync command again without the --dry-run flag (and with progress bar and log file flags)? (y/n) \e[0m' SHOULD_CONTINUE
if [ "$SHOULD_CONTINUE" = "y" ]; then
  echo "Running: $RSYNC_COMMAND"
  if [ ! -e "$LOG_PATH" ]; then
    echo "Date:" > "$LOG_PATH"
    date >> "$LOG_PATH"
    system_profiler SPHardwareDataType >> "$LOG_PATH"
    echo "Hostname:" >> "$LOG_PATH"
    echo "$(uname -n)" >> "$LOG_PATH"
  fi
  echo "Rsync command:" >> "$LOG_PATH"
  echo "$RSYNC_COMMAND" >> "$LOG_PATH"
  eval "$RSYNC_COMMAND"
  if [ "$IS_REMOTE_COPY" -eq "1" ]; then
    scp "$LOG_PATH" "${DEST_DIR_NO_SLASH}_rsync_log.txt" ${original_path%/*}
  fi
  echo $'\e[32mThe backup was successful.\e[0m'
else
  echo "Exiting."
  exit 2
fi
