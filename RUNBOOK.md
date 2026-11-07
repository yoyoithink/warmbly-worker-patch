# Runbook: patched Warmbly worker (NetEase Enterprise Mail fix)

Scope: **only the `worker` service** runs a patched image. The other ten services stay on the official images. Nothing in `.env`, the database or any volume is touched.

- Patched image: `ghcr.io/yoyoithink/warmbly-worker:<tag>` (built by `.github/workflows/build-worker.yml` from the official tag + `patches/0001-netease-status-examine-fallback.patch`; `VERSION` equals the official tag)
- Official image (rollback target): `ghcr.io/warmbly/warmbly/worker:<tag>`
- Coolify service uuid: `ykmssbfg9qn2u5ubwmdbw4c6`; worker container: `worker-ykmssbfg9qn2u5ubwmdbw4c6`
- Affected mailbox: `xingyu.liu@tendata.cn` (id `7b30d50d-ecfb-4342-a054-9a71d37997b6`)

## What the bug is

NetEase answers `STATUS` for a folder with a non-ASCII name (`已发送`, `已删除`, ...) under the literal name `"???"`. go-imap `v2.0.0-beta.7` pairs a STATUS reply to its command by mailbox name and drops one it cannot pair, so the cursors come back as zero. `folders.go` turns that into `ErrMailServerUnreachable` and aborts every sync pass. The patch reads the cursors of such folders with a read-only `EXAMINE` instead. Servers that answer STATUS correctly follow exactly the old code path.

## One-time setup

1. Create the public repo `yoyoithink/warmbly-worker-patch` containing this tree.
2. Actions → *build-worker* → Run workflow, tag `v0.6.60` (the running version). Wait for green.
3. GitHub → profile → Packages → `warmbly-worker` → Package settings → Change visibility → **Public** (the VPS pulls anonymously).
4. `scripts\check-worker-image.ps1 v0.6.60` must print `OK`.

## Cutover (staged)

**G0 baseline** (read-only, before touching anything): `list_mailboxes` JSON; on the VPS `docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}'`, `docker inspect worker-ykmssbfg9qn2u5ubwmdbw4c6 --format '{{.Image}} {{.State.StartedAt}}'`; copy the compose from Coolify (*Edit Compose File*) to `compose.before.yml`.

**G2 pre-pull** (no disruption): on the VPS
```bash
docker pull ghcr.io/yoyoithink/warmbly-worker:v0.6.60
docker image inspect ghcr.io/yoyoithink/warmbly-worker:v0.6.60 --format '{{.Id}} {{.Architecture}} {{.Size}} {{.Config.Entrypoint}}'
```
Architecture must match the host (`uname -m`: x86_64 → amd64).

**Change** in Coolify → service → *Edit Compose File*, **only** the worker line:
```diff
-    image: 'ghcr.io/warmbly/warmbly/worker:${WARMBLY_TAG:-prod}'
+    image: 'ghcr.io/yoyoithink/warmbly-worker:${WARMBLY_TAG:-prod}'
```
Do not add environment variables (every service uses `env_file: .env`; a new variable would recreate all of them). Save, redeploy. Only the worker's config changed, so only the worker is recreated (~1–2 min; web/API/tracking unaffected).

**G3 verification**
- `docker ps`: worker `Up`, image `ghcr.io/yoyoithink/warmbly-worker:v0.6.60`; every other container's `StartedAt` unchanged vs G0.
- `docker logs --since 20m worker-ykmssbfg9qn2u5ubwmdbw4c6 2>&1 | grep 7b30d50d`: no new `mail sync error` / `mail server still unreachable` after the restart (≥ 3 passes, 5–20 min).
- `list_mailboxes`: `xingyu.liu@tendata.cn` no longer lists the connection failure (its DMARC/DKIM warning is separate); the other 60 mailboxes identical to G0.
- `get_mailbox`: `last_synced_at` advancing.
- Re-check after 24 h.

If a *different* error appears after the first full pass, that is a second NetEase quirk (e.g. identical huge `UIDNEXT` across folders, no CONDSTORE/UNSELECT), not a regression of this fix: capture the log line and extend the patch series.

## Rollback (≈ 2 min, no data impact)

Trigger: worker crash-loops, other mailboxes regress vs G0, or any unexpected container restart.

In Coolify restore the single worker line to `image: 'ghcr.io/warmbly/warmbly/worker:${WARMBLY_TAG:-prod}'` (or paste `compose.before.yml`) and redeploy. The swap is same-version and schema-neutral: no database or volume rollback is needed. Confirm the worker image ID equals the G0-recorded one. The state after rollback is the known pre-fix state (NetEase mailbox failing, all else healthy).

## Upgrading Warmbly later (keeps the fix)

1. Choose the target tag `vX.Y.Z`, read the release notes as usual.
2. **Gate:** `scripts\check-worker-image.ps1 vX.Y.Z`.
   - `OK` → continue.
   - `MISSING` → Actions → *build-worker* → Run workflow with that tag, wait for green, re-run the script.
   - Build red at *Apply the source patch* → upstream changed `folders.go`: rebase the patch (small, three insertions) and push; the workflow reruns. Or, as a conscious fallback, point the worker line back at the official image for that upgrade (only the NetEase mailbox fails again).
3. Change `WARMBLY_TAG` in Coolify and redeploy as always. The worker line uses the same `${WARMBLY_TAG}`, so backend/consumer/worker stay on one version.

What can undo the fix, and how it shows up:
- Re-importing the official compose into Coolify resets the worker line → the NetEase error returns (safe direction: official image). Re-apply the one-line change.
- Upstream fixes the bug → the workflow's probe detects it, mirrors the official image under our name, and the patch becomes a no-op. Then revert the worker line to the official image and archive this repo.
- GitHub disables scheduled workflows after 60 days without repo activity → the gate above triggers builds on demand; also run the workflow manually once a month.

## Upstream

`upstream/ISSUE.md` and `upstream/PR.md` are ready to submit to `warmbly/warmbly` (run `make fmt` and `make lint` on a checkout first).
