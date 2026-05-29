#!/bin/bash -l

set -e

SSH_MASTER_OPEN=0

: "${INPUT_WPE_SSHG_KEY_PRIVATE?Required secret not set.}"
: "${INPUT_DEPLOYS?DEPLOYS is required. Provide a JSON array of deploy jobs.}"

resolve_environment() {
    if [[ "$GITHUB_REF" == "refs/heads/${INPUT_PRD_BRANCH}" ]]; then
        export WPE_ENV_NAME=$INPUT_PRD_ENV
    elif [[ -n "$INPUT_STG_BRANCH" && "$INPUT_STG_BRANCH" != "STAGE_BRANCH_HERE" && "$GITHUB_REF" == "refs/heads/${INPUT_STG_BRANCH}" ]]; then
        export WPE_ENV_NAME=$INPUT_STG_ENV
    elif [[ -n "$INPUT_DEV_BRANCH" && "$INPUT_DEV_BRANCH" != "DEV_BRANCH_HERE" && "$GITHUB_REF" == "refs/heads/${INPUT_DEV_BRANCH}" ]]; then
        export WPE_ENV_NAME=$INPUT_DEV_ENV
    else
        echo "FAILURE: Branch ${GITHUB_REF} does not match PRD_BRANCH, STG_BRANCH, or DEV_BRANCH." && exit 1
    fi

    echo "Deploying ${GITHUB_REF} to ${WPE_ENV_NAME}..."

    WPE_SSH_HOST="${WPE_ENV_NAME}.ssh.wpengine.net"
    WPE_SSH_USER="${WPE_ENV_NAME}@${WPE_SSH_HOST}"
    WPE_FULL_HOST="${WPE_SSH_USER}"
}

validate_deploys() {
    if ! echo "$INPUT_DEPLOYS" | jq -e 'type == "array" and length > 0' >/dev/null; then
        echo "ERROR: DEPLOYS must be a non-empty JSON array."
        exit 1
    fi

    DEPLOY_COUNT=$(echo "$INPUT_DEPLOYS" | jq 'length')
    for ((i = 0; i < DEPLOY_COUNT; i++)); do
        src=$(echo "$INPUT_DEPLOYS" | jq -r ".[$i].src // empty")
        flags=$(echo "$INPUT_DEPLOYS" | jq -r ".[$i].flags // empty")
        if [[ -z "$src" || -z "$flags" ]]; then
            echo "ERROR: DEPLOYS[$i] requires non-empty src and flags."
            exit 1
        fi
    done

    echo "Validated ${DEPLOY_COUNT} deploy job(s)."
}

prep_paths_and_lint() {
    local job src
    local -A prepped_srcs=()

    while IFS= read -r job; do
        src=$(echo "$job" | jq -r '.src')
        if [[ -n "${prepped_srcs[$src]:-}" ]]; then
            continue
        fi
        prepped_srcs[$src]=1

        if [[ ! -e "$src" ]]; then
            echo "WARNING: src path does not exist (may be a glob): ${src}"
        else
            echo "Prepping file perms for ${src}..."
            find "$src" -type d -exec chmod 775 {} \;
            find "$src" -type f -exec chmod 664 {} \;
        fi

        if [[ "${INPUT_PHP_LINT^^}" == "TRUE" ]]; then
            echo "PHP lint for ${src}..."
            while IFS= read -r -d '' file; do
                php -l "$file"
            done < <(find "$src" -name "*.php" -print0 2>/dev/null || true)
        fi
    done < <(echo "$INPUT_DEPLOYS" | jq -c '.[]')

    if [[ "${INPUT_PHP_LINT^^}" != "TRUE" ]]; then
        echo "Skipping PHP linting."
    else
        echo "PHP lint successful for all checked paths."
    fi
}

teardown_ssh() {
    if [[ "$SSH_MASTER_OPEN" -eq 1 ]]; then
        ssh -O exit -o ControlPath="${SSH_CONTROL_PATH}" "$WPE_FULL_HOST" 2>/dev/null || true
        SSH_MASTER_OPEN=0
    fi
}

setup_ssh() {
    if [[ ! -d ${HOME}/.ssh ]]; then
        mkdir "${HOME}/.ssh"
        SSH_PATH="${HOME}/.ssh"
        mkdir "${SSH_PATH}/ctl/"
        chmod -R 700 "$SSH_PATH"
    else
        SSH_PATH="${HOME}/.ssh"
        echo "Using established SSH path..."
    fi

    WPE_SSHG_KEY_PRIVATE_PATH="${SSH_PATH}/github_action"
    printf '%s' "$INPUT_WPE_SSHG_KEY_PRIVATE" > "$WPE_SSHG_KEY_PRIVATE_PATH"
    chmod 600 "$WPE_SSHG_KEY_PRIVATE_PATH"

    KNOWN_HOSTS_PATH="${SSH_PATH}/known_hosts"
    : > "$KNOWN_HOSTS_PATH"
    ssh-keyscan "$WPE_SSH_HOST" >> "$KNOWN_HOSTS_PATH" 2>/dev/null
    if [[ ! -s "$KNOWN_HOSTS_PATH" ]]; then
        echo "ERROR: Could not populate known_hosts for ${WPE_SSH_HOST}."
        exit 1
    fi
    chmod 644 "$KNOWN_HOSTS_PATH"

    SSH_IDENTITY=(-i "$WPE_SSHG_KEY_PRIVATE_PATH")
    SSH_KNOWN_HOSTS=(-o "StrictHostKeyChecking=yes" -o "UserKnownHostsFile=${KNOWN_HOSTS_PATH}")
    SSH_CONTROL_PATH="${SSH_PATH}/ctl/%C"
    RSYNC_RSH="ssh -p 22 -i ${WPE_SSHG_KEY_PRIVATE_PATH} -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${KNOWN_HOSTS_PATH} -o ControlPath=${SSH_CONTROL_PATH}"

    trap teardown_ssh EXIT

    ssh -nNf "${SSH_IDENTITY[@]}" "${SSH_KNOWN_HOSTS[@]}" -o ControlMaster=yes -o ControlPath="${SSH_CONTROL_PATH}" "$WPE_FULL_HOST"
    SSH_MASTER_OPEN=1
    echo "Master SSH connection established."
}

run_rsync_jobs() {
    local job index=0 total
    local name src dest flags destination

    total=$(echo "$INPUT_DEPLOYS" | jq 'length')

    while IFS= read -r job; do
        index=$((index + 1))
        name=$(echo "$job" | jq -r '.name // empty')
        src=$(echo "$job" | jq -r '.src')
        dest=$(echo "$job" | jq -r '.dest // ""')
        flags=$(echo "$job" | jq -r '.flags')
        destination="${WPE_SSH_USER}:sites/${WPE_ENV_NAME}/${dest}"

        if [[ -n "$name" ]]; then
            echo "Deploy job ${index}/${total}: ${name}"
        else
            echo "Deploy job ${index}/${total}"
        fi

        rsync --rsh="$RSYNC_RSH" $flags --exclude-from='/exclude.txt' "$src" "$destination"
    done < <(echo "$INPUT_DEPLOYS" | jq -c '.[]')
}

maybe_cache_clear() {
    if [[ "${INPUT_CACHE_CLEAR^^}" == "TRUE" ]]; then
        echo "Clearing page and CDN cache..."
        ssh -p 22 "${SSH_IDENTITY[@]}" "${SSH_KNOWN_HOSTS[@]}" -o ControlPath="${SSH_CONTROL_PATH}" "$WPE_FULL_HOST" \
            "cd sites/${WPE_ENV_NAME} && wp --skip-plugins --skip-themes page-cache flush && wp --skip-plugins --skip-themes cdn-cache flush"
    elif [[ "${INPUT_CACHE_CLEAR^^}" != "FALSE" ]]; then
        echo "CACHE_CLEAR must be TRUE or FALSE." && exit 1
    fi
}

resolve_environment
validate_deploys
prep_paths_and_lint
setup_ssh
run_rsync_jobs
maybe_cache_clear
teardown_ssh
trap - EXIT

echo "SUCCESS: Your code has been deployed to WP Engine!"
