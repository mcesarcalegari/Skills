# Global install

`install.sh` makes this repo's skills and agents available in every Claude Code session by symlinking them into `~/.claude`. The repo stays the single source of truth.

```bash
./install.sh --dry-run   # preview, changes nothing
./install.sh             # install
```

Requires Bash and `python3`.

## What `install.sh` does

1. **Prunes stale links.** Removes links that point into this repo when their source is gone or now excluded.
2. **Links skills.** Each `skills/<name>/` with a `SKILL.md` becomes `~/.claude/skills/<name>`. `react-*` and `spring-*` are excluded; edit `is_excluded` in the script to change that.
3. **Links agents.** Each `agents/*.md` becomes `~/.claude/agents/<name>.md`.
4. **Lists skills by name only.** Adds `"<name>": "name-only"` under `skillOverrides` in `~/.claude/settings.json` for each linked skill, so Claude sees names without descriptions. Existing values are kept, and so are all other settings. Manual-only skills (`disable-model-invocation: true`) are left out.

Safeguards:

- An existing file, folder or link that points elsewhere is never overwritten. It is skipped with a `WARN`.
- Before changing settings, the script copies them to `~/.claude/settings.json.bak`. Invalid JSON is left untouched and the script exits with an error (links may already have been updated).
- Running it again with nothing to update makes no changes.

## Update routine

```bash
git pull && ./install.sh
```

| What changed in the repo | Is `git pull` enough? |
|---|---|
| Existing skill or agent edited | Yes |
| Skill or agent added, removed or renamed | No, re-run `install.sh` |
| `disable-model-invocation` or the exclusion list changed | No, re-run `install.sh` |

If a skill becomes manual-only, also remove its old `name-only` entry from settings by hand. If a change doesn't appear, run `/reload-skills` or start a new session.

## Verification

Run from the repo root:

```bash
# A second run should end with "settings.json: no changes" and "0 link change(s)"
./install.sh

# Count the links into this repo (48 skills and 7 agents as of 2026-11-23)
find ~/.claude/skills -maxdepth 1 -type l -lname "$PWD/*" | wc -l
find ~/.claude/agents -maxdepth 1 -type l -lname "$PWD/*" | wc -l

# Dangling links: should print nothing
find -L ~/.claude/skills ~/.claude/agents -maxdepth 1 -type l

# Settings are valid JSON; count the name-only entries (45 as of 2026-11-23)
python3 -c 'import json, os; d = json.load(open(os.path.expanduser("~/.claude/settings.json"))); print(list(d.get("skillOverrides", {}).values()).count("name-only"))'
```

Then, in a new Claude Code session, check that `/handoff` is offered and ask Claude which agent types it has available.

## Risks and limitations

- **Weaker automatic triggering.** Without descriptions, Claude is less likely to choose a skill by itself. `/<name>` still works; describe the skills in each project's `CLAUDE.md`.
- **Pulled changes go live.** Edits to linked skills and agents apply to all projects, so review upstream changes before pulling. Switching branches also changes what is installed.
- **Symlinked agents are undocumented.** The Claude Code docs cover symlinked skill folders but not agent files. Agents loaded correctly on 2.1.330; re-check after upgrades.
- **Moving the repo breaks the links.** Delete the old links first, then re-run the script. Until then it treats them as someone else's and skips them.
- **One-level backup.** `settings.json.bak` is overwritten by the next run that changes settings.
- **Name conflicts.** Personal skills override project skills of the same name.

Known issues in the current content, intentionally left unchanged:

- **`verify`** replaces the bundled `/verify` and compares against `master` by default. Use `/verify --base=main` where needed.
- **`finalize`** depends on `.claude/hooks/foldio-verify/*.sh` and on coverage skills that aren't in this repo.
- **`react-data-layer` and `react-integration-testing`** hardcode paths under `/Users/philipplackner/`. Both are currently excluded.

## Uninstall

Run from the repo root. Remove `-delete` first to preview.

```bash
find ~/.claude/skills ~/.claude/agents -maxdepth 1 -type l -lname "$PWD/*" -delete
```

Then remove this repo's `name-only` entries from `skillOverrides` in `~/.claude/settings.json`.
