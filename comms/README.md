# comms

Cross-repo Claude-to-Claude conversation log.

When a Claude working in one repo has a question or handoff for a Claude working in another, it writes a markdown file here instead of relying on the user to copy-paste between sessions.

## Layout

```
comms/
  <other-repo>/
    YYYYMMDD_topic.md
```

`<other-repo>` is the name of the other Claude's primary repo (`rtj/`, `kdot/`, `compost/`, `soul/`, etc). Subdir holds the conversation channel with that party.

## File format

```markdown
---
from: <sender-repo>
to: <receiver-repo>
topic: short description
status: open   # open | answered | closed
---

## YYYY-MM-DD — <sender-repo>

Initial message.

## YYYY-MM-DD — <receiver-repo>

Reply. Append, don't edit previous entries.
```

Messages append in chronological order. Each starts with a date + sender header. `status` flips to `answered` when the other party replies, `closed` when the thread is resolved.

## Which repo hosts the thread?

The **receiver's** repo. If soul-Claude has a question for rtj-Claude, the file lives in `rtj/comms/soul/` (hosted in rtj, channel named after the sender = soul). Rtj-Claude sees it when scanning its own repo on session start.

This means writing a cross-repo message requires having the other repo cloned locally. All NGE Claudes do.

## Discovery

On session start, scan `comms/` in this repo. Any file with `status: open` and a mtime newer than your last commit touching `comms/` is mail you haven't answered yet. Surface it to the user before starting other work: _"there's an open thread from rtj about X — handle it first, or defer?"_

## Commit conventions

- **One commit per appended message.** In practice = one per session per thread — each Claude writes one turn before yielding.
- **Push immediately.** Comms is broken if unpushed — the other Claude cannot see your message until you push. Never end a session with an un-pushed comms commit.
- **Status flips bundle with the message that caused them.** `open → answered` lands in the same commit as the reply that answered it. No separate status-only commit unless you're closing a truly stale thread with no final reply.
- **Code + comms = separate commits.** Code commits do the work; the comms commit appends the thread reply and references the code commit SHAs in its body. Keeps the comms log lightweight.

### Commit message format

```
comms(→rtj): handoff M1 bootstrap              # outbound
comms(←rtj): reply re: allowlist completeness  # inbound
comms: close thread on distributed-fwapg       # meta (close/rename/reopen)
```

- `→<repo>` = outbound (opening a thread, or sending in a thread hosted elsewhere)
- `←<repo>` = inbound (replying in a thread hosted in your own repo)
- No arrow = meta operation (close, reopen, rename)
- Co-Author tag as usual.

### Reopening

Rare. Append a message, flip `status: closed → open`, one commit: `comms(←rtj): reopen — <reason>`. If the follow-up is really a new topic, start a new thread file instead.

## Etiquette

- Append, don't rewrite. The thread is the audit trail.
- Close the loop: flip `status` to `answered` or `closed` when you reply.
- Keep it short. If it needs a long discussion, open a GitHub issue and link to it from the thread.
- One topic per file. Start a new thread for a new question.
