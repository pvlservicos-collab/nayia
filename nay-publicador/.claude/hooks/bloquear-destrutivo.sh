#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Bloqueia TRUNCATE, DROP TABLE ou DELETE FROM
# a menos que o comando contenha a palavra CONFIRMADO. Roda sempre, inclusive
# em modo automático, porque o bloqueio acontece antes do prompt de permissão.
set -euo pipefail

input="$(cat)"
command="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"

if [ -z "$command" ]; then
  exit 0
fi

if printf '%s' "$command" | grep -Eiq '(truncate|drop[[:space:]]+table|delete[[:space:]]+from)'; then
  if ! printf '%s' "$command" | grep -qi 'confirmado'; then
    jq -n --arg cmd "$command" '{
      systemMessage: "🛑 Comando bloqueado pelo hook bloquear-destrutivo: contém TRUNCATE, DROP TABLE ou DELETE FROM sem a palavra CONFIRMADO.",
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: ("Bloqueado por bloquear-destrutivo.sh: comando destrutivo sem CONFIRMADO explícito. Comando: " + $cmd)
      }
    }'
    exit 0
  fi
fi

exit 0
