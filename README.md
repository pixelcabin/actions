# Pixelcabin GitHub Actions

Public composite actions for Shopify theme CI/CD. Each action lives in its own directory and is referenced by path and version tag.

## Actions

| Action | Use |
|--------|-----|
| [`production-deploy`](./production-deploy) | Manual production deploy: backup current theme, push built theme |

More actions (staging deploy, PR preview, and so on) will be added as sibling directories.

## Production deploy

The action runs in **your theme repo** after checkout and build. It does not check out a second repository, zip artifacts, or use a PAT.

### What the theme repo provides

- `shopify.theme.toml` with production environments (`store`, `theme`, `ignore` for JSON and `settings_data.json`)
- GitHub **Environments** whose names match those toml sections (for per-store secrets)
- A workflow that builds the theme, then calls this action

### What the action does

1. Looks up that theme's current name with `shopify theme list --id`, then duplicates it (`shopify theme duplicate`) as an unpublished backup named `Backup of {theme name} (YYYY-MM-DD HH:MM)` in UTC. The theme name is shortened so the timestamp still fits Shopify's 50-character limit. The copy is made on Shopify, so fonts and JSON stay intact.
2. Pushes your built theme to the same theme id, honoring toml `ignore` so merchant JSON and settings are not overwritten

Set `SHOPIFY_CLI_THEME_TOKEN` on the job (typically from `secrets.SHOPIFY_STORE_ACCESS_TOKEN` on each GitHub Environment). Set `SHOPIFY_FLAG_FORCE: 1` at workflow or job level for non-interactive CLI.

Use Node **22+** in the caller workflow (for example via `.nvmrc` and `actions/setup-node`). Current Shopify CLI requires it.

### Example workflow

Save as `.github/workflows/manual-deploy-production-shopify-theme.yml`. Adjust the matrix to your production environments.

```yaml
name: Manual Deploy to Production

on:
  workflow_dispatch:

env:
  SHOPIFY_FLAG_FORCE: 1

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  deploy-production:
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    timeout-minutes: 12
    strategy:
      matrix:
        environment_target: [production_eu, production_us]
    environment:
      name: ${{ matrix.environment_target }}
    env:
      SHOPIFY_CLI_THEME_TOKEN: ${{ secrets.SHOPIFY_STORE_ACCESS_TOKEN }}
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version-file: .nvmrc
          cache: npm

      - name: Build theme
        run: |
          npm ci
          npm run build:production

      - uses: pixelcabin/actions/production-deploy@v1
        with:
          environment-target: ${{ matrix.environment_target }}
          path: .
          slack-webhook: ${{ secrets.SLACK_WEBHOOK_URL }}
```

If theme files live under `shop/`, set `path: shop`. Omit `slack-webhook` to skip Slack.

The `if: github.ref == 'refs/heads/main'` guard is on the **job**, not on the action, so you can use a test branch without that guard when validating the action.

The production environment in `shopify.theme.toml` must set a numeric `theme` id. `theme duplicate` copies that remote theme; it does not fall back to the live theme.

### Secrets

| Secret | Where |
|--------|--------|
| `SHOPIFY_STORE_ACCESS_TOKEN` | Each GitHub Environment (Admin API app with `read_themes` / `write_themes`) |
| `SLACK_WEBHOOK_URL` | Optional, repo or environment secret |

## Versioning

Reference a **major** tag in theme workflows:

```yaml
uses: pixelcabin/actions/production-deploy@v1
```

For each non-breaking release:

1. Tag the commit `v1.1.0` (immutable).
2. Move the `v1` tag to the same commit and push both tags.

The next workflow run resolves `@v1` to that commit. Workflows already running keep the commit they resolved at start.

Pin `@v1.0.0` or a full commit SHA if you should not move automatically. Breaking changes get a new major tag (`v2`); leave `@v1` on the 1.x line until callers opt in.
