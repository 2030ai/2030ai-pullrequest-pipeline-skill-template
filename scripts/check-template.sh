#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

require_grep() {
  local pattern="$1"
  local file="$2"
  grep -Eq "$pattern" "$file" || fail "expected pattern '$pattern' in $file"
}

require_exact_grep() {
  local line="$1"
  local file="$2"
  grep -Fxq "$line" "$file" || fail "expected line '$line' in $file"
}

command -v ruby >/dev/null 2>&1 || fail "ruby is required for YAML validation"

skills="pullrequest endsession"

for skill in $skills; do
  require_file ".agents/skills/$skill/SKILL.md"
  require_file ".agents/skills/$skill/agents/openai.yaml"

  require_exact_grep "name: $skill" ".agents/skills/$skill/agents/openai.yaml"
  require_exact_grep "display_name: \"/$skill\"" ".agents/skills/$skill/agents/openai.yaml"
  require_exact_grep "# /$skill" ".agents/skills/$skill/SKILL.md"

  for platform in .claude .codex .cursor; do
    link="$platform/skills/$skill"
    expected="../../.agents/skills/$skill"
    [ -L "$link" ] || fail "missing symlink: $link"
    actual="$(readlink "$link")"
    [ "$actual" = "$expected" ] || fail "$link points to '$actual', expected '$expected'"
    require_file "$link/SKILL.md"
  done
done

require_file ".agents/skills/pullrequest/reviewers.yaml"
require_file ".agents/pullrequest-maintainership.example.md"

ruby -ryaml -e '
paths = ARGV
paths.each { |path| YAML.load_file(path) || abort("empty YAML: #{path}") }
' \
  .agents/skills/pullrequest/reviewers.yaml \
  .agents/skills/pullrequest/agents/openai.yaml \
  .agents/skills/endsession/agents/openai.yaml

ruby -ryaml -e '
cfg = YAML.load_file(".agents/skills/pullrequest/reviewers.yaml")
modes = cfg.fetch("review_modes")
reviewers = cfg.fetch("reviewers").keys
%w[medium max].each do |mode|
  selected = modes.fetch(mode).fetch("reviewers")
  missing = selected - reviewers
  abort("#{mode} references unknown reviewers: #{missing.join(", ")}") unless missing.empty?
end
abort("medium must not require ultrareview") unless modes.fetch("medium").fetch("ultrareview") == "none"
abort("max must use user_run_handoff") unless modes.fetch("max").fetch("ultrareview") == "user_run_handoff"
'

require_grep 'curl -fsSL ".*/\.agents/skills/pullrequest/SKILL.md"' README.md
require_grep 'curl -fsSL ".*/\.agents/skills/pullrequest/reviewers.yaml"' README.md
require_grep 'curl -fsSL ".*/\.agents/skills/pullrequest/agents/openai.yaml"' README.md
require_grep 'curl -fsSL ".*/\.agents/skills/endsession/SKILL.md"' README.md
require_grep 'curl -fsSL ".*/\.agents/skills/endsession/agents/openai.yaml"' README.md
require_grep 'curl -fsSL ".*/\.agents/pullrequest-maintainership.example.md"' README.md
require_grep 'pullrequest-maintainership.md' README.md
require_grep 'pullrequest-maintainership.example.md' README.md

echo "Template validation passed"
