#!/bin/bash -l

set -e

: ${INPUT_WPE_SSHG_KEY_PRIVATE?Required secret not set.}

if [[ "$GITHUB_REF" == "refs/heads/${INPUT_PRD_BRANCH}" ]]; then
    export WPE_ENV_NAME=$INPUT_PRD_ENV
elif [[ -n "$INPUT_STG_BRANCH" && "$INPUT_STG_BRANCH" != "STAGE_BRANCH_HERE" && "$GITHUB_REF" == "refs/heads/${INPUT_STG_BRANCH}" ]]; then
    export WPE_ENV_NAME=$INPUT_STG_ENV
elif [[ -n "$INPUT_DEV_BRANCH" && "$INPUT_DEV_BRANCH" != "DEV_BRANCH_HERE" && "$GITHUB_REF" == "refs/heads/${INPUT_DEV_BRANCH}" ]]; then
    export WPE_ENV_NAME=$INPUT_DEV_ENV
else
    echo "FAILURE: Branch ${GITHUB_REF} does not match PRD_BRANCH, STG_BRANCH, or DEV_BRANCH." && exit 1
fi

echo "Deploying $GITHUB_REF to $WPE_ENV_NAME..."

# Deploy Vars
WPE_SSH_HOST="$WPE_ENV_NAME.ssh.wpengine.net"
DIR_PATH="$INPUT_TPO_PATH"
SRC_PATH="$INPUT_TPO_SRC_PATH"

# Set up our user and path
WPE_SSH_USER="$WPE_ENV_NAME"@"$WPE_SSH_HOST"
WPE_FULL_HOST="$WPE_SSH_USER"
WPE_DESTINATION="$WPE_SSH_USER":sites/"$WPE_ENV_NAME"/"$DIR_PATH"


# Setup our SSH Connection & use keys
if [ ! -d ${HOME}/.ssh ]; then 
    mkdir "${HOME}/.ssh" 
    SSH_PATH="${HOME}/.ssh" 
    mkdir "${SSH_PATH}/ctl/"
    # Set Key Perms 
    chmod -R 700 "$SSH_PATH"
  else 
  SSH_PATH="${HOME}/.ssh" 
  echo "using established SSH KEY path...";
fi

# Write private key from base64 (single-line secret avoids env newline/escaping issues in Docker actions).
WPE_SSHG_KEY_PRIVATE_PATH="${SSH_PATH}/github_action"
printf '%s' "$INPUT_WPE_SSHG_KEY_PRIVATE" | tr -d '\n' | base64 -d > "$WPE_SSHG_KEY_PRIVATE_PATH"
chmod 600 "$WPE_SSHG_KEY_PRIVATE_PATH"
if ! head -n1 "$WPE_SSHG_KEY_PRIVATE_PATH" | grep -q -- '-----BEGIN'; then
    echo "ERROR: Decoded key does not look like PEM. Store the secret as base64: base64 -w 0 < key (Linux) or base64 -i key (macOS)."
    exit 1
fi

# Establish known hosts
KNOWN_HOSTS_PATH="${SSH_PATH}/known_hosts"
ssh-keyscan "$WPE_SSH_HOST" >> "$KNOWN_HOSTS_PATH" 2>/dev/null
if [[ ! -s "$KNOWN_HOSTS_PATH" ]]; then
    echo "ERROR: Could not populate known_hosts for ${WPE_SSH_HOST}."
    exit 1
fi
chmod 644 "$KNOWN_HOSTS_PATH"

SSH_IDENTITY=(-i "$WPE_SSHG_KEY_PRIVATE_PATH")
SSH_KNOWN_HOSTS=(-o "StrictHostKeyChecking=yes" -o "UserKnownHostsFile=${KNOWN_HOSTS_PATH}")
SSH_CONTROL_PATH="${SSH_PATH}/ctl/%C"

echo "prepping file perms..."
find "$SRC_PATH" -type d -exec chmod 775 {} \;
find "$SRC_PATH" -type f -exec chmod 664 {} \;
echo "file perms set..."

# pre deploy php lint
if [ "${INPUT_PHP_LINT^^}" == "TRUE" ]; then
    echo "Begin PHP Linting."
    for file in $(find "$SRC_PATH/" -name "*.php"); do
        php -l "$file"
        status=$?
        if [[ $status -ne 0 ]]; then
            echo "FAILURE: Linting failed - $file :: $status" && exit 1
        fi
    done
    echo "PHP Lint Successful! No errors detected!"
else 
    echo "Skipping PHP Linting."
fi

# post deploy script 
if [[ -n ${INPUT_SCRIPT} ]]; then 
    SCRIPT="&& sh ${INPUT_SCRIPT}"; 
  else 
    SCRIPT=""
fi 

# post deploy cache clear
if [ "${INPUT_CACHE_CLEAR^^}" == "TRUE" ]; then
    CACHE_CLEAR="&& wp --skip-plugins --skip-themes page-cache flush && wp --skip-plugins --skip-themes cdn-cache flush"
  elif [ "${INPUT_CACHE_CLEAR^^}" == "FALSE" ]; then
      CACHE_CLEAR=""
  else echo "CACHE_CLEAR must be TRUE or FALSE only... Cache not cleared..."  && exit 1;
fi

# Deploy via SSH
# setup master ssh connection
ssh -nNf "${SSH_IDENTITY[@]}" "${SSH_KNOWN_HOSTS[@]}" -o ControlMaster=yes -o ControlPath="${SSH_CONTROL_PATH}" "$WPE_FULL_HOST"

echo "!!! MASTER SSH CONNECTION ESTABLISHED !!!"
RSYNC_RSH="ssh -p 22 -i ${WPE_SSHG_KEY_PRIVATE_PATH} -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${KNOWN_HOSTS_PATH} -o ControlPath=${SSH_CONTROL_PATH}"
rsync --rsh="$RSYNC_RSH" $INPUT_FLAGS --exclude-from='/exclude.txt' "$SRC_PATH" "$WPE_DESTINATION"

# post deploy script and cache clear
if [[ -n ${SCRIPT} || -n ${CACHE_CLEAR} ]]; then
    ssh -p 22 "${SSH_IDENTITY[@]}" "${SSH_KNOWN_HOSTS[@]}" -o ControlPath="${SSH_CONTROL_PATH}" "$WPE_FULL_HOST" "cd sites/${WPE_ENV_NAME} ${SCRIPT} ${CACHE_CLEAR}"
fi

# close master ssh
ssh -O exit -o ControlPath="${SSH_CONTROL_PATH}" "$WPE_FULL_HOST"

echo "SUCCESS: Your code has been deployed to WP Engine!"
