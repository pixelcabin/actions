# Next steps

Review of `production-deploy` after the backup, theme-lookup, and Slack work.

The deploy sequence is sound: duplicate the remote theme, then push that same theme id, and still notify Slack if the push fails. The risks worth fixing are operational. A few of them can fail a deploy that already went live, or eventually block deploys entirely.

## Bugs and robustness

**Backups will fill the theme library, and then deploys stop.** `theme duplicate` creates a real unpublished theme, and those count toward the store cap (20 on most plans, 100 on Plus). `--force` only skips the confirm prompt. It does not replace an existing theme. Once the library is full, duplicate fails with "Maximum number of themes reached" and the push never runs. That is the failure mode that will show up after a few weeks of deploys. Prune first: list themes, delete the oldest names starting with `Backup of `, keep the last N, and never delete role `main`.

**A post-deploy step can mark a successful push as failed.** `Read package version` and `Notify Slack` both use `if: !cancelled()`, so they run after a good push, and neither has `continue-on-error`. `get-package-version.sh` exits non-zero if `jq` fails or `package.json` is invalid. A Slack payload that fails to parse does the same. The job goes red, Slack reports `failure`, and the obvious response is to re-run, which takes another backup and pushes again.

```yaml
- name: Read package version
  id: package-version
  if: ${{ !cancelled() }}
  shell: bash
  run: bash "$GITHUB_ACTION_PATH/scripts/get-package-version.sh"

- name: Notify Slack
  if: ${{ inputs.slack-webhook != '' && !cancelled() }}
  uses: slackapi/slack-github-action@v4
```

The payload is a double-quoted YAML string with the theme name dropped in raw. A theme named `Summer "Drop"` or one containing a newline breaks the YAML, and the Slack step fails the job. Build the body with `jq -n --arg` and pass `payload-file-path`, and set `continue-on-error` on both of these steps.

**The Slack message can claim a backup that was never created.** The backup name is computed before `theme duplicate`. If duplicate fails, that step's output still exists, and the message always prints `*Backup:* …`. Give the duplicate and push steps ids and include their outcomes. On a cancelled run the Slack step is skipped entirely (`!cancelled()`), so a deploy killed mid-push sends nothing.

**Theme lookup hides the real CLI error.** In `get-theme-name-from-id.sh`, stderr is discarded and a non-zero exit is swallowed:

```bash
RAW=$(shopify theme list -e="$ENVIRONMENT_TARGET" --id="$THEME_ID" --json 2>/dev/null || true)
JSON=$(printf '%s\n' "$RAW" | sed -n '/^[[:space:]]*[[{]/,$p')
THEME_NAME=$(printf '%s\n' "$JSON" | jq -r 'if type == "array" then .[0].name else .name end' 2>/dev/null || true)
```

A bad token, a network failure, and a wrong theme id all surface as "No theme named for id …". Keep stderr, and print the raw output when `jq` does not find a name. Also require exactly one result, and record `role`. For a production action, refusing to push unless that role is `main` would catch a stale id left pointing at a draft.

**The theme id parser keeps every digit on the line.** `gsub(/[^0-9]/, "")` turns `theme = '138722410659' # rolled 2026-09-01` into `13872241065920260901`. Parse the quoted value. While you are there, point the lookup at `inputs.path` as well as the repo root. `theme push` already honors `path`; the toml read does not. The current theme repo keeps `shopify.theme.toml` at the root, so this is latent.

**Push does not pin the theme you just backed up.**

```yaml
- name: Push theme to production
  run: shopify theme push -a -e="${{ inputs.environment-target }}" --path="${{ inputs.path }}"
```

Duplicate is locked to the id from the toml. Push trusts environment resolution only. Pass `-t` with that same id. There is also no check that `layout/theme.liquid` exists under `path` before `-a` overwrites the live theme, and no check that this environment's `ignore` still covers `config/settings_data.json`. `production_eu_backup` in the test repo is the same theme id with no ignores. Pointing the action at it would overwrite merchant JSON.

**Backup names collide within the same minute.** The stamp is `YYYY-MM-DD HH:MM`. A re-run in that minute asks Shopify for a theme name that already exists, duplicate fails, and the push never happens. Seconds cost three characters off the already-truncated theme name (21 today) and remove that collision. Write the name to `$GITHUB_OUTPUT` with a heredoc delimiter so a `%` or newline in the merchant's theme name cannot corrupt the output.

**The example workflow will cancel a live push.** `cancel-in-progress: true` plus the matrix default `fail-fast: true` means a second dispatch, or a failure on one store, cancels the other job mid-`theme push`. Use `cancel-in-progress: false`, `fail-fast: false`, and a concurrency group that includes the environment name.

## Different approaches

The shape of the action (caller builds, this repo only backs up and pushes) is the right split. Pull-then-push is the wrong way to take the backup.

Worth adding, in roughly this order:

1. **Retention before duplicate.** Keep the last 5–10 `Backup of …` themes. This is what keeps the action deployable a month from now.
2. **A preflight step.** Node 22+, `SHOPIFY_CLI_THEME_TOKEN` set, toml theme id present, role `main`, `settings_data.json` ignored, `layout/theme.liquid` present under `path`. Fail before duplicate, with the actual reason.
3. **`--json` on duplicate.** Capture the new theme id and the name Shopify actually stored. Put that id in the Slack message as an admin link, and publish it as an action output so a caller can roll back with `theme publish`.
4. **A job summary as well as Slack.** `$GITHUB_STEP_SUMMARY` is on the run page even when the webhook is down. Include commit SHA and ref next to `package.json` version. Theme repos often ship several deploys on the same version, so the SHA is what tells two runs apart.
5. **Pin `slackapi/slack-github-action` to a commit SHA.** `@v4` moves. The CLI pin at `4.8.0` is already the right idea.
6. **Fixture tests for the two toml/name scripts.** The 50-character cutoff and the theme-id parser are pure bash and easy to get wrong. A few `shopify.theme.toml` fixtures would lock them.

Do not auto-publish the backup if push fails. A push can apply part of the theme and still exit non-zero, but it can also exit non-zero after the upload succeeded. Automatic rollback can undo a good deploy. The useful version is the backup id in Slack, plus a documented `theme publish` of that id.
