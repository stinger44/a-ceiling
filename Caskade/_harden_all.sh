#!/bin/bash
# Hardening для aesa и remna (node_d — проблема с ключом, пропускаем)
set -euo pipefail

SCRIPT="/d/Gravity/Caskade/_remote_harden_steps.sh"

harden() {
  local alias="$1"
  echo ""
  echo "████████████████████████████████████████"
  echo "  Hardening: ${alias}"
  echo "████████████████████████████████████████"
  scp "${SCRIPT}" "${alias}:/tmp/harden.sh"
  ssh "${alias}" "bash /tmp/harden.sh && rm /tmp/harden.sh"
  echo "✅ ${alias} — готов"
}

harden aesa
harden remna

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  aesa + remna захарднены ✅           ║"
echo "╚══════════════════════════════════════╝"
