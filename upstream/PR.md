# imap: read folder cursors by EXAMINE when a STATUS reply cannot be paired (NetEase Enterprise Mail)

Fixes the issue "NetEase Enterprise Mail: every IMAP sync fails with server unreachable when a folder name is non-ASCII".

## What

NetEase answers `STATUS` for non-ASCII folders with the mailbox name masked as `"???"`. go-imap beta.7 pairs STATUS replies to commands by name and drops unmatched ones, so `Status().Wait()` returns zeros without an error, and `listFoldersCapped` turned that into `ErrMailServerUnreachable`, aborting the whole listing and every sync pass.

## How

- `listFoldersCapped` is split: `listFoldersOnce` is the previous body (LIST, then STATUS per folder). A STATUS result that is the zero value with an empty `Mailbox` (`unmatchedStatus`) for a folder whose name contains a non-ASCII character (`nonASCIIName`) is no longer an error: the folder is kept and recorded as pending. An ASCII name cannot be masked this way, so an empty answer for one still fails as before; `TestFoldersIncompleteStatusRemainsRetryable` keeps passing unchanged.
- `fillUnmatchedStatus` then reads the cursors of the pending folders with a read-only SELECT (EXAMINE) through the existing `selectMailbox` funnel, under `c.mu` → `lifecycle.RLock` → `begin()`, the same order every other selection-changing path uses. The lock is taken only on this path, so servers that answer STATUS correctly keep the lock-free listing.
- Error handling mirrors the original block: `ErrMailResourceNotFound` retires the folder, anything else aborts. A SELECT that still yields zero cursors returns `ErrMailServerUnreachable` as before, so a genuinely broken server fails the same way.
- `ListFolders` runs right after `ReleaseMailbox` in the sync loop, so selecting during the listing does not disturb a resumed sync step.

## Tests

`folders_masked_status_test.go`, using the existing `rewritingServer` harness:

- `TestFoldersSurviveMaskedStatusReplies`: folders `已发送`, `已删除`, `Templates`; STATUS names containing a UTF-7 shift are rewritten to `"???"`. Asserts the listing succeeds with cursors identical to the unmasked run, and exactly two EXAMINE commands are sent (none in the unmasked run).
- `TestMaskedStatusLeavesAsciiFoldersAlone`: ASCII folders are untouched and no EXAMINE is sent.

The first test fails on the pristine code with `SERVER_UNREACHABLE` (our CI runs the test against the unpatched tag to prove it).

## Checklist

- [ ] `make fmt`
- [ ] `make lint`
- [ ] `go test ./internal/client/smtpimap/...`
