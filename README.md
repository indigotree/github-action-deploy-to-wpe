# GitHub Action to deploy WordPress projects to WP Engine

Indigo Tree fork of the WP Engine deploy action. Deploy code from a GitHub repo to a WP Engine environment via SSH Gateway and rsync. Deploy a full site directory or a sub-directory of your WordPress install. Options include PHP lint, custom rsync flags, page and CDN cache clearing, and a post-deploy script.

Pin `uses:` to a [release tag or commit SHA](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#using-versioned-actions) after updating this action.

## Setup Instructions

Follow along with the [video tutorial here!](https://wpengine-2.wistia.com/medias/crj1lp3qke) (upstream WP Engine; concepts still apply).

1. **MAIN.YML SETUP**

- Copy the following `main.yml` to `.github/workflows/main.yml` in the root of your WordPress project/repo, replacing `PRD_BRANCH`, `PRD_ENV`, and the action pin. Optional vars can be specified as well. See [Environment Variables & Secrets](#environment-variables--secrets).

2. **SSH PRIVATE KEY SETUP IN GITHUB**

- [Generate a new SSH key pair](https://wpengine.com/support/ssh-keys-for-shell-access/#Generate_New_SSH_Key) if you have not already done so.

- Encode the private key as a single-line base64 string (required for this action):

  ```bash
  # Linux
  base64 -w 0 < path/to/private_key > secret.txt

  # macOS
  base64 -i path/to/private_key > secret.txt
  ```

- Add the base64 output to [Repository Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets#creating-encrypted-secrets-for-a-repository) or [Organization Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets#creating-encrypted-secrets-for-an-organization). Name the secret `WPE_SSHG_KEY_PRIVATE`.

**NOTE:** Organization secrets let all repos use one SSH key for deploys. That key connects to every install available to its WP Engine user.

3. **SSH PUBLIC KEY SETUP IN WP ENGINE**

- Add the SSH public key to WP Engine SSH Gateway Key settings. [This guide shows how.](https://wpengine.com/support/ssh-gateway/#Add_SSH_Key)

  **NOTE:** This action does not use WP Engine GitPush or GitPush SSH keys [from the user portal.](https://wpengine.com/support/git/#Add_SSH_Key_to_User_Portal)

4. Git push your site repo. The action runs on push to a configured branch.

View progress and logs under the **Actions** tab in your repo.

## Example GitHub Action workflow

Branch names in `PRD_BRANCH`, `STG_BRANCH`, and `DEV_BRANCH` must match the pushed ref exactly (`refs/heads/<name>`). For example, `PRD_BRANCH: main` deploys only on push to `main`, not `feature/main`. Mirror branch names in `on.push.branches` when possible.

### Simple main.yml

```yaml
name: Deploy to WP Engine
on:
  push:
    branches:
      - main

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: GitHub Action Deploy to WP Engine
        uses: indigotree/github-action-deploy-to-wpe@v0.5.3
        with:
          WPE_SSHG_KEY_PRIVATE: ${{ secrets.WPE_SSHG_KEY_PRIVATE }}
          PRD_BRANCH: main
          PRD_ENV: prodsitehere
```

### Extended main.yml

```yaml
name: Deploy to WP Engine
on:
  push:
    branches:
      - main
      - feature/stage
      - feature/dev

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: GitHub Action Deploy to WP Engine
        uses: indigotree/github-action-deploy-to-wpe@v0.5.3
        with:
          WPE_SSHG_KEY_PRIVATE: ${{ secrets.WPE_SSHG_KEY_PRIVATE }}
          PHP_LINT: TRUE
          FLAGS: -azvr --inplace --delete --exclude=".*" --exclude-from=.deployignore
          CACHE_CLEAR: TRUE
          TPO_SRC_PATH: "wp-content/themes/genesis-child-theme/"
          TPO_PATH: "wp-content/themes/genesis-child-theme/"
          PRD_BRANCH: main
          PRD_ENV: prodsitehere
          STG_BRANCH: feature/stage
          STG_ENV: stagesitehere
          DEV_BRANCH: feature/dev
          DEV_ENV: devsitehere
```

Replace `@v0.5.3` with your chosen tag or commit SHA after merging updates to this action.

## Environment Variables & Secrets

### Required

| Name                   | Type    | Usage                                                                                    |
| ---------------------- | ------- | ---------------------------------------------------------------------------------------- |
| `PRD_BRANCH`           | string  | Git branch to deploy from (exact name, e.g. `main`). Must match `refs/heads/<name>`.     |
| `PRD_ENV`              | string  | WP Engine environment name to deploy to.                                                 |
| `WPE_SSHG_KEY_PRIVATE` | secrets | Base64-encoded private SSH key (single line). See setup step 2.                          |

### Optional

| Name           | Type   | Usage                                                                                                                                                                                                                                               |
| -------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `STG_BRANCH`   | string | Staging branch name (exact match). Omit placeholder default or leave unset if unused.                                                                                                 |
| `STG_ENV`      | string | WP Engine staging environment name.                                                                                                                                                 |
| `DEV_BRANCH`   | string | Development branch name (exact match).                                                                                                                                              |
| `DEV_ENV`      | string | WP Engine development environment name.                                                                                                                                             |
| `PHP_LINT`     | bool   | Set to TRUE to run `php -l` on PHP files before deploy. Default `FALSE`.                                                                                                            |
| `FLAGS`        | string | Optional rsync flags (e.g. `--delete`, `--exclude-from`). Defaults to a non-destructive deploy.                                                                                     |
| `CACHE_CLEAR`  | bool   | When TRUE (default), runs WP-CLI `page-cache flush` and `cdn-cache flush` after deploy.                                                                                             |
| `TPO_SRC_PATH` | string | Source path to deploy from. Default `.` (repo root).                                                                                                                                |
| `TPO_PATH`     | string | Destination path on the server. Default WordPress root.                                                                                                                            |
| `SCRIPT`       | string | Remote shell script path (relative to site root), run after rsync.                                                                                                                  |

### Further reading

- [Defining environment variables in GitHub Actions](https://docs.github.com/en/actions/reference/environment-variables)
- [Storing secrets in GitHub repositories](https://docs.github.com/en/actions/reference/encrypted-secrets)
- This action does not restrict deployable paths; use [WP Engine .gitignore templates](https://wpengine.com/support/git/#Add_gitignore) and rsync excludes as needed.

### Legal

See the LICENSE file for license information.

Copyright (C) 2021-present, Indigo Tree Digital Ltd.

Based on prior work from https://github.com/wpengine/github-action-wpe-site-deploy  
Copyright (c) 2021 WP Engine
