# g6xai/claude-plugins

Claude Code plugins for g6x.ai engineering teams.

## Install

Add to your `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "g6xai": {
      "source": {
        "source": "github",
        "repo": "g6xai/claude-plugins"
      }
    }
  },
  "enabledPlugins": {
    "fleet@g6xai": true
  }
}
```

Restart Claude Code.

## Plugins

| Plugin | Description |
|--------|-------------|
| [fleet](plugins/fleet/) | SE ops platform — bootstrap any repo for autonomous dev with Linear/Notion sync |

## For Engineers

Once installed, go into any repo and run:

```
/fleet-init
```

Fleet detects your repo state and handles the rest.

## Developing

Clone this repo locally for iterating on plugins:

```bash
git clone git@github.com:g6xai/claude-plugins.git /Users/Shared/code/claude-plugins
```

Use `directory` source instead of `github` in your settings for live edits:

```json
{
  "extraKnownMarketplaces": {
    "g6xai-dev": {
      "source": {
        "source": "directory",
        "path": "/Users/Shared/code/claude-plugins"
      }
    }
  },
  "enabledPlugins": {
    "fleet@g6xai-dev": true
  }
}
```

Edit any skill/agent/command file, restart Claude Code, changes take effect.
