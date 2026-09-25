# Token rules for every session

The user's rule, for every session: watch token usage and make no useless
calls.

- No polling loops or timed status checks. Check a build once per push.
- Don't re-read files you already know, or re-fetch what hasn't changed.
- Don't send "understood" or status replies. Message only when you're
  blocked, need a decision, or something landed.
- One short message per finished task, with the commit hash.
- Keep messages short: what changed, and what the reader has to do.
- Don't build fake, test-only or placeholder code unless the lead asks for it.
- Don't duplicate another session's work. Check `notes/` first.
