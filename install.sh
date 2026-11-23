#!/usr/bin/env bash
# Symlinks this repo's skills and agents into ~/.claude and lists the skills by
# name only. Safe to re-run: never overwrites anything it doesn't own.
#
# Usage: ./install.sh [--dry-run]
set -euo pipefail

DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  *) echo "Usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CLAUDE_HOME="$HOME/.claude"
SKILLS_DIR="$CLAUDE_HOME/skills"
AGENTS_DIR="$CLAUDE_HOME/agents"
changes=0
warnings=0
NAME_ONLY=()
PRUNED=()

is_excluded() {
  case "$1" in react-*|spring-*) return 0 ;; *) return 1 ;; esac
}

run() {
  changes=$((changes + 1))
  if [ "$DRY_RUN" = 0 ]; then "$@"; fi
}

# link SOURCE DEST: succeeds if DEST is (or would be) our link
link() {
  if [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ]; then return 0; fi
  if [ -e "$2" ] || [ -L "$2" ]; then
    echo "WARN   $2 already exists and is not ours; skipped" >&2
    warnings=$((warnings + 1))
    return 1
  fi
  echo "LINK   $2"
  run ln -s "$1" "$2"
}

# Remove links into this repo whose target is gone or now excluded
prune() {
  local entry target name
  for entry in "$1"/*; do
    [ -L "$entry" ] || continue
    target="$(readlink "$entry")"
    name="$(basename "$entry")"
    case "$target" in "$REPO/$2"/*) ;; *) continue ;; esac
    if [ "$2" = skills ]; then
      if [ -f "$target/SKILL.md" ] && ! is_excluded "$name"; then continue; fi
      PRUNED+=("$name")
    elif [ -f "$target" ]; then
      continue
    fi
    echo "PRUNE  $entry"
    run rm "$entry"
  done
}

if [ "$DRY_RUN" = 0 ]; then mkdir -p "$SKILLS_DIR" "$AGENTS_DIR"; fi

prune "$SKILLS_DIR" skills
prune "$AGENTS_DIR" agents

for dir in "$REPO"/skills/*/; do
  dir="${dir%/}"
  name="$(basename "$dir")"
  [ -f "$dir/SKILL.md" ] || continue
  if is_excluded "$name"; then continue; fi
  link "$dir" "$SKILLS_DIR/$name" || continue
  # Manual-only skills are already hidden from the listing; leave them alone.
  if ! awk '/^---[[:space:]]*$/{c++; next} c==1' "$dir/SKILL.md" \
      | grep -Eq '^disable-model-invocation:[[:space:]]*true'; then
    NAME_ONLY+=("$name")
  fi
done

for file in "$REPO"/agents/*.md; do
  [ -f "$file" ] || continue
  link "$file" "$AGENTS_DIR/$(basename "$file")" || true
done

# ${arr[@]+...} keeps empty arrays safe under set -u in bash 3.2
DRY_RUN=$DRY_RUN python3 -I - "$CLAUDE_HOME/settings.json" \
  ${NAME_ONLY[@]+"${NAME_ONLY[@]}"} -- ${PRUNED[@]+"${PRUNED[@]}"} <<'PY'
import json, os, shutil, sys

path, rest = sys.argv[1], sys.argv[2:]
split = rest.index("--")
add, drop = rest[:split], rest[split + 1:]

settings = {}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as f:
            settings = json.load(f)
    except ValueError as e:
        sys.exit(f"ERROR  {path} is not valid JSON, left untouched: {e}")
if not isinstance(settings, dict) or not isinstance(settings.get("skillOverrides", {}), dict):
    sys.exit(f"ERROR  unexpected structure in {path}, left untouched")

overrides = dict(settings.get("skillOverrides", {}))
before = dict(overrides)
for name in drop:
    if overrides.get(name) == "name-only":
        del overrides[name]
for name in add:
    overrides.setdefault(name, "name-only")

if overrides == before:
    print("settings.json: no changes")
    sys.exit()
added, removed = len(overrides.keys() - before.keys()), len(before.keys() - overrides.keys())
print(f"settings.json: skillOverrides +{added} -{removed}")
if os.environ["DRY_RUN"] == "1":
    sys.exit()
settings["skillOverrides"] = overrides
if os.path.exists(path):
    shutil.copy2(path, path + ".bak")
# Write in place so a symlinked settings.json stays a symlink
with open(path, "w", encoding="utf-8") as f:
    f.write(json.dumps(settings, indent=2, ensure_ascii=False) + "\n")
PY

if [ "$DRY_RUN" = 1 ]; then prefix="Dry run: would make "; else prefix="Done: "; fi
echo "${prefix}${changes} link change(s), ${warnings} warning(s)"
