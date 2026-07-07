---
name: gif-demo-create
description: Generate an animated GIF demo of the Headroom admin interface using Playwright
---

# GIF Demo Create

Generate an animated GIF tour of the Headroom admin interface (dashboard, users, teams, keys, usage with user history and semantic search).

## Trigger

`/gif-demo-create` or `/gif-demo-create --url https://your-proxy.com`

## Requirements

- Playwright + Chromium installed
- `HEADROOM_API_KEY` in env or passed via `--api-key`
- Proxy running and accessible

## Usage

```bash
# Default (localhost:8787, reads HEADROOM_API_KEY from env)
uv run python ~/git/util/scripts/headroom/gif-demo-create/generate-admin-demo.py

# Custom URL + explicit key
uv run python ~/git/util/scripts/headroom/gif-demo-create/generate-admin-demo.py \
  --url https://proxy.example.com \
  --api-key "hr_..." \
  --output /tmp/demo.gif
```

The script:
1. Logs in (not shown in GIF)
2. Captures Dashboard, Users, Teams, Keys, Usage overview
3. Interacts with User History combobox (types "admin", clicks Load)
4. Performs a Semantic Search query

Output: animated GIF at `/tmp/admin-demo.gif` (or custom `--output`).
