# GitHub Action to deploy WordPress projects to WP Engine

Indigo Tree fork of the WP Engine deploy action. Deploy from a GitHub repo to a WP Engine environment via SSH Gateway and rsync.

One workflow step can run **multiple rsync jobs** over a **single SSH connection** by passing a `DEPLOYS` JSON array.

Pin `uses:` to a [commit SHA or branch](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#using-versioned-actions).

## Setup Instructions

1. **Workflow**

- Add a deploy workflow under `.github/workflows/` (see [Example](#example-platform-deploy-step)).
- Set `DEPLOYS` to a JSON array of jobs (see [DEPLOYS schema](#deploys-schema)).
- Configure branch and environment inputs (`PRD_BRANCH`, `PRD_ENV`, etc.).

2. **SSH private key (GitHub)**

- [Generate an SSH key pair](https://wpengine.com/support/ssh-keys-for-shell-access/#Generate_New_SSH_Key) if needed.
- Encode the private key as a single-line base64 string:

  ```bash
  # Linux
  base64 -w 0 < path/to/private_key > secret.txt

  # macOS
  base64 -i path/to/private_key > secret.txt
  ```

- Store the output as repository or organization secret `WPE_SSHG_KEY_PRIVATE`.

3. **SSH public key (WP Engine)**

- Add the public key to [SSH Gateway](https://wpengine.com/support/ssh-gateway/#Add_SSH_Key). This action does not use GitPush keys.

4. Push to a configured branch. View logs under **Actions**.

Branch names must match the pushed ref exactly (`refs/heads/<name>`). Use `on.push.branches` to match `PRD_BRANCH`, `STG_BRANCH`, and `DEV_BRANCH`.

## DEPLOYS schema

`DEPLOYS` is a JSON **array** inline in the workflow step (`DEPLOYS: |`).

Each object:

| Field   | Required | Description |
| ------- | -------- | ----------- |
| `src`   | Yes      | Source path in the checkout (globs allowed, e.g. `wp-content/plugins/foo-*`) |
| `flags` | Yes      | Rsync flags for this job (e.g. `-azvr --inplace --exclude-from=.deployignore`) |
| `dest`  | No       | Destination directory on the server (default `""` = site root relative) |
| `name`  | No       | Label for logs only |

Jobs run **in array order** on one SSH session.

## Example platform deploy step

Replace multiple `uses:` deploy steps with one step like this (pin `@<commit-sha>` after merging this action):

```yaml
      - name: Deploy to WP Engine
        uses: indigotree/github-action-deploy-to-wpe@<pin>
        with:
          WPE_SSHG_KEY_PRIVATE: ${{ secrets.WPE_SSHG_KEY_PRIVATE }}
          CACHE_CLEAR: FALSE
          PHP_LINT: FALSE
          DEV_BRANCH: ${{ env.DEV_BRANCH }}
          STG_BRANCH: ${{ env.STG_BRANCH }}
          PRD_BRANCH: ${{ env.PRD_BRANCH }}
          DEV_ENV: ${{ env.DEV_ENV }}
          STG_ENV: ${{ env.STG_ENV }}
          PRD_ENV: ${{ env.PRD_ENV }}
          DEPLOYS: |
            [
              {
                "name": "plugins-once",
                "src": "wp-content/plugins",
                "dest": "wp-content",
                "flags": "-azvr --inplace --ignore-existing --exclude-from=.deployignore"
              },
              {
                "name": "project-plugins",
                "src": "wp-content/plugins/indigotree-site-*",
                "dest": "wp-content/plugins",
                "flags": "-azvr --inplace --exclude-from=.deployignore"
              },
              {
                "name": "modules",
                "src": "wp-content/platform",
                "dest": "wp-content",
                "flags": "-azvr --inplace --delete --delete-delay --exclude-from=.deployignore"
              },
              {
                "name": "mu-plugins",
                "src": "wp-content/mu-plugins",
                "dest": "wp-content",
                "flags": "-azvr --inplace --exclude-from=.deployignore"
              },
              {
                "name": "theme-and-rest",
                "src": ".",
                "dest": "",
                "flags": "-azvr --inplace --exclude-from=.deployignore --exclude=/*.* --exclude=_wpeprivate/ --exclude=wp-admin/ --exclude=wp-includes/ --exclude=wp-content/plugins/ --exclude=wp-content/platform/ --exclude=wp-content/mu-plugins/ --exclude=wp-content/uploads/ --exclude=wp-content/upgrade*/ --exclude=wp-content/drop-ins/ --exclude=wp-content/languages/ --exclude=mysql.sql --include=/wp-content/themes/ --include=/wp-content/themes/indigotree-theme-2026/*** --exclude=/wp-content/themes/*"
              }
            ]
```

Minimal single-job example:

```yaml
      - uses: actions/checkout@v4
      - name: Deploy to WP Engine
        uses: indigotree/github-action-deploy-to-wpe@<pin>
        with:
          WPE_SSHG_KEY_PRIVATE: ${{ secrets.WPE_SSHG_KEY_PRIVATE }}
          PRD_BRANCH: main
          PRD_ENV: myinstall
          DEPLOYS: |
            [
              {
                "src": ".",
                "dest": "",
                "flags": "-azvr --inplace --exclude-from=.deployignore"
              }
            ]
```

## Migration from older action inputs

If you previously used several deploy steps with `TPO_SRC_PATH`, `TPO_PATH`, and `FLAGS`:

| Old input        | DEPLOYS field |
| ---------------- | ------------- |
| `TPO_SRC_PATH`   | `src`         |
| `TPO_PATH`       | `dest`        |
| `FLAGS`          | `flags`       |

1. Merge each old step into one object in the `DEPLOYS` array (preserve order).
2. Use a single `uses:` step with `DEPLOYS: |`.
3. Set `CACHE_CLEAR: FALSE` unless you want a post-deploy flush (default is `false`).
4. Pin `uses:` to the commit SHA that includes `DEPLOYS` support.

Removed inputs: `TPO_SRC_PATH`, `TPO_PATH`, `FLAGS`, `SCRIPT`.

## Inputs

### Required

| Name                   | Type    | Usage |
| ---------------------- | ------- | ----- |
| `DEPLOYS`              | string  | JSON array of deploy jobs (inline in workflow YAML). |
| `PRD_BRANCH`           | string  | Production branch name (exact match to `refs/heads/<name>`). |
| `PRD_ENV`              | string  | WP Engine production environment name. |
| `WPE_SSHG_KEY_PRIVATE` | secrets | Base64-encoded private SSH key. |

### Optional

| Name         | Type   | Usage |
| ------------ | ------ | ----- |
| `STG_BRANCH` | string | Staging branch (exact match). Leave placeholder if unused. |
| `STG_ENV`    | string | WP Engine staging environment. |
| `DEV_BRANCH` | string | Development branch (exact match). |
| `DEV_ENV`    | string | WP Engine development environment. |
| `PHP_LINT`   | bool   | `TRUE` to run `php -l` on each job `src` before deploy. Default `false`. |
| `CACHE_CLEAR`| bool   | `TRUE` to flush page and CDN cache after all jobs. Default `false`. |

## Further reading

- [GitHub Actions environment variables](https://docs.github.com/en/actions/reference/environment-variables)
- [Encrypted secrets](https://docs.github.com/en/actions/reference/encrypted-secrets)
- [WP Engine .gitignore templates](https://wpengine.com/support/git/#Add_gitignore)

## Legal

See LICENSE.

Copyright (C) 2021-present, Indigo Tree Digital Ltd.

Based on prior work from https://github.com/wpengine/github-action-wpe-site-deploy  
Copyright (c) 2021 WP Engine
