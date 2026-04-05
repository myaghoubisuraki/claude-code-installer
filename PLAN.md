# Project Plan — Claude Code Secure Installer

> This file is the living project log. Every step is recorded here so that even
> if you switch to a new chat, the assistant can read this and know exactly where
> to continue.

---

## Goal

Build a GitHub-hosted repository that anyone can clone and run to get Claude Code
fully installed end-to-end on their system — securely, on any OS.

---

## Phases

### Phase 1 — Core Installer ✅ COMPLETE

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1.1 | Create project directory structure | ✅ Done | `install.sh`, `install.ps1`, `install.bat`, `verify.*` |
| 1.2 | Write Unix installer (`install.sh`) | ✅ Done | Covers macOS + all major Linux distros |
| 1.3 | Write Windows installer (`install.ps1`) | ✅ Done | winget + direct MSI fallback with SHA256 |
| 1.4 | Write Windows batch launcher (`install.bat`) | ✅ Done | Double-click friendly |
| 1.5 | Write verify scripts | ✅ Done | `verify.sh` + `verify.ps1` |
| 1.6 | Write `README.md` | ✅ Done | Full docs, quick start, security notes |
| 1.7 | Write `PLAN.md` (this file) | ✅ Done | Project log for cross-chat continuity |
| 1.8 | Initialize git repo | ✅ Done | Local git init complete |

---

### Phase 2 — Security Review ✅ COMPLETE

| # | Task | Status | Notes |
|---|------|--------|-------|
| 2.1 | Run Codex adversarial review on `install.sh` + `install.ps1` | ✅ Done | 7 findings: 3 HIGH, 2 MEDIUM, 2 LOW |
| 2.2 | Fix HIGH: curl-pipe-sudo NodeSource pattern | ✅ Done | Replaced with signed apt repo (GPG key + sources.list) |
| 2.3 | Fix HIGH: `eval "$(fnm env)"` arbitrary execution | ✅ Done | Parse only known env vars with allowlist regex |
| 2.4 | Fix HIGH: Git installer no signature check | ✅ Done | Authenticode verification before execution |
| 2.5 | Fix MEDIUM: nvm.sh sourced via manipulable $HOME | ✅ Done | Resolve real home via getent passwd + ownership check |
| 2.6 | Fix MEDIUM: Execution policy persisted to user profile | ✅ Done | Changed to Process scope (session-only) |
| 2.7 | Fix LOW: Predictable temp paths (TOCTOU) | ✅ Done | Random names via GetRandomFileName() |
| 2.8 | Fix LOW: Unqualified npm resolved from PATH | ✅ Done | Resolve absolute path before calling |

---

### Phase 3 — GitHub Publishing ⏳ PENDING

| # | Task | Status | Notes |
|---|------|--------|-------|
| 3.1 | Create GitHub repository | ⏳ Pending | User to provide repo name / confirm |
| 3.2 | Replace `YOUR_USERNAME` in README with real username | ⏳ Pending | |
| 3.3 | Add `LICENSE` file (MIT) | ⏳ Pending | |
| 3.4 | Initial commit and push | ⏳ Pending | |
| 3.5 | Add GitHub Actions CI workflow | ⏳ Pending | Lint scripts on PR |

---

### Phase 4 — Enhancements ⏳ FUTURE

| # | Task | Status | Notes |
|---|------|--------|-------|
| 4.1 | Silent/unattended install mode (`--yes` flag) | ⏳ Future | For deploying to many machines |
| 4.2 | `uninstall.sh` / `uninstall.ps1` | ⏳ Future | Clean removal |
| 4.3 | Config file support (pre-set preferences) | ⏳ Future | |
| 4.4 | GitHub Releases with versioned archives | ⏳ Future | |

---

## Architecture Decisions

### Why not `curl | bash`?
Piping a URL directly to bash is a major security risk — the server can serve
different content to different clients. This repo requires a `git clone` first,
so users can inspect the scripts before running.

### Why npm official registry?
We explicitly pin `--registry https://registry.npmjs.org/` during install and
warn if a custom registry is detected. This prevents supply-chain attacks via
a malicious npm mirror.

### Why SHA256 for Node.js on Windows?
The Windows installer downloads a `.msi` from nodejs.org and verifies its
checksum against the official `SHASUMS256.txt` file before running it. If the
hash doesn't match, the install is aborted immediately.

### Why no sudo on Windows?
The PowerShell script runs as a standard user and uses `winget` (user-scope)
or user-local MSI install. Admin elevation is never requested — Claude Code's
npm package installs fine in user scope.

---

## How to Continue in a New Chat

If you start a new Claude Code session and want to continue this project:

1. Tell Claude: **"Continue the claude-code-installer project"**
2. Claude will read this file and the memory at
   `~/.claude/projects/.../memory/project_claude_installer.md`
3. The next step is **Phase 2 — Security Review** using the Codex plugin

---

## Change Log

| Date | Change |
|------|--------|
| 2026-04-05 | Phase 1 complete — all installer scripts and docs created |
| 2026-04-05 | Phase 2 complete — Codex security review run; all 7 findings fixed |
