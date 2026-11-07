# NetEase Enterprise Mail (qiye.163.com): every IMAP sync fails with "server unreachable" when a folder name is non-ASCII

## Summary

A mailbox on NetEase Enterprise Mail (`imap.qiye.163.com:993`) connects, authenticates and lists folders, but every sync pass aborts with the generic `ErrMailServerUnreachable` ("Mail server sync connection failed") and `last_synced_at` never advances.

## Cause

NetEase's default folders have Chinese names (`已发送`, `已删除`, `草稿箱`, ...). The client sends `STATUS "&XfJT0ZAB-" (UIDNEXT UIDVALIDITY MESSAGES)` for them, and the server replies with the mailbox name masked as the literal string `???`:

```
* STATUS "???" (...)
```

(captured from the wire and inspected byte by byte: the name is the three bytes `3f 3f 3f`, not a UTF-7 or UTF-8 encoding of the requested name.)

`github.com/emersion/go-imap/v2@v2.0.0-beta.7` pairs a STATUS reply with its command by mailbox name (`cmd.mailbox == data.Mailbox`) and silently drops one that does not match; there is no unilateral STATUS handler in beta.7. `Status(...).Wait()` therefore returns a zero `StatusData` and no error. In `internal/client/smtpimap/imap/folders.go` (`listFoldersCapped`):

```go
if st == nil || st.UIDValidity == 0 || st.UIDNext == 0 {
    return FolderListing{}, errx.ErrMailServerUnreachable
}
```

This aborts the whole listing, so no folder of the mailbox is ever synced. `LIST`, `EXAMINE`/`SELECT` of the same folders work normally on that server, so credentials, TLS and network are fine.

Skip-folders cannot work around it: it is applied after `ListFolders`, and NetEase system folders cannot be deleted.

## Environment

- Warmbly v0.6.60 (also present on `main` and v0.6.78 as of 2026-11-05)
- Server: NetEase Enterprise Mail, IMAP over TLS 993, no CONDSTORE, no UNSELECT

## Proposed fix

When a STATUS result was never paired with its reply (zero value, empty `Mailbox`), read that folder's `UIDVALIDITY`/`UIDNEXT`/message count from a read-only `EXAMINE` instead. Servers that answer STATUS normally take exactly the existing path. See the PR.
