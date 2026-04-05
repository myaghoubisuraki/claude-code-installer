# Post-install verification — Windows
$pass = 0; $fail = 0
function Check { param($label,$cmd)
  if (Get-Command $cmd -EA SilentlyContinue) {
    $ver = & $cmd --version 2>$null | Select-Object -First 1
    Write-Host "  [OK]  ${label}: $ver" -ForegroundColor Green; $script:pass++
  } else {
    Write-Host "  [!!]  ${label}: NOT FOUND" -ForegroundColor Red; $script:fail++
  }
}
Write-Host ""; Write-Host "  Claude Code — Verification"; Write-Host "  ─────────────────────────"
Check "node"   "node"
Check "npm"    "npm"
Check "git"    "git"
Check "claude" "claude"
Write-Host ""
if ($fail -eq 0) { Write-Host "  All checks passed." -ForegroundColor Green }
else             { Write-Host "  $fail check(s) failed." -ForegroundColor Red }
Write-Host ""; exit $fail
