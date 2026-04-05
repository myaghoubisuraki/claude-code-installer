#!/usr/bin/env bash
# Post-install verification — macOS & Linux
set -euo pipefail
PASS=0; FAIL=0
check() {
  local label="$1"; shift
  if "$@" &>/dev/null; then
    echo "  ✓  $label: $("$@" 2>/dev/null | head -1)"
    ((PASS++))
  else
    echo "  ✗  $label: NOT FOUND"
    ((FAIL++))
  fi
}
echo ""
echo "  Claude Code — Verification"
echo "  ─────────────────────────"
check "node"   node --version
check "npm"    npm --version
check "git"    git --version
check "claude" claude --version
echo ""
[ "$FAIL" -eq 0 ] && echo "  All checks passed." || echo "  $FAIL check(s) failed."
echo ""
exit "$FAIL"
