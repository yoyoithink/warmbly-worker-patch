# warmbly-worker-patch

Builds `ghcr.io/yoyoithink/warmbly-worker:<tag>`: the official Warmbly worker plus a small patch that makes NetEase Enterprise Mail (qiye.163.com) mailboxes sync. See `RUNBOOK.md` for cutover, verification, rollback and the upgrade gate.

- `patches/0001-netease-status-examine-fallback.patch` – fix + regression test
- `.github/workflows/build-worker.yml` – builds every official release tag >= v0.6.60; fails loudly if the patch no longer applies
- `scripts/check-worker-image.ps1` – pre-upgrade gate
- `upstream/` – issue and PR text for `warmbly/warmbly`

Licensed under Apache-2.0, as is the upstream project; the patch is a derivative of its source.
