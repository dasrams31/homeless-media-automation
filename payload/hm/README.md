# Homeless Media (HM) pipeline

Automated AI-news pipeline: 1 topic/day, full-auto, for one brand's
Instagram + Threads + Facebook Page (+ optional blog). Installed by
`homeless-media-automation/install.sh`; do not move files out of this
layout, the cron body references these exact paths.

## The 4 agents

1. **Scout** (`scout.py`) — ingests RSS into `news.db` (SQLite, dedupe by
   URL). Default feeds (edit the FEEDS list in scout.py to localise):
   TechCrunch AI, The Verge, Ars Technica, MIT Tech Review, Google Blog,
   OpenAI Blog, CNN Indonesia Tech, Antara Tekno.
   `scout.py --test` reports which feeds return entries.
2. **Filter** (`filter.py`) — viral score 0-100 per unused item:
   recency 30 + AI-keyword relevance 35 + source tier 15 + hook signals 20.
   `filter.py --top N` prints top N as JSON. Mark used:
   `UPDATE items SET used=1 WHERE id=?`
3. **Writer** — the cron worker (AI): headline (<=90ch), sub-headline,
   3-4 carousel points, one directly-usable element (prompt/template/
   checklist/steps), Threads chain (<=500ch each, exactly 1 topic hashtag
   per post), IG caption (<=2200ch), FB text (keep under ±1000ch), optional
   blog JSON. Natural voice, no em/en-dash, facts only from the source
   article. Rules live in `../engagement-playbook.md` + `../learnings.md`.
4. **Designer** (`designer.py`) — 2K (2048x2048) carousel PNGs with the
   brand header standard (category badge top-left, mascot lockup +
   brand label top-right). `--theme auto` rotates 4 full design sets daily
   (FRAME / KORAN / MAJALAH / TERMINAL); `--theme layar` frames a source
   screenshot as the main evidence. Cover shows NO source URL, only the
   source name + a GESER (swipe) button. Always visually verify the cover
   PNG before posting; shorten headline/points and regenerate on overflow.

## Runtime layout

- `hm/venv/` — python venv (feedparser + Pillow); run every script with it
- `hm/news.db` — SQLite items (url UNIQUE, used flag)
- `hm/out/YYYY-MM-DD/` — carousel PNGs per run (`out/smoke-test/` is the
  installer reference render)
- `hm/work/YYYY-MM-DD/` — caption text files for the day. NEVER use /tmp
  for captions: a service restart once wiped /tmp mid-run and the IG post
  went out without its caption. Verify before any retry that nothing was
  already posted (check the platform post lists) — never double-post, and
  never delete + repost similar content (see playbook, ATURAN DARI DATA).
- `hm/visuals/` — generated hero images
- `../posted.log` — one line per published edition
- `../blog/*.json` + `../images/` — blog output (only when blog is enabled
  in the install config)

## Posting notes (verified CLI behaviour)

- `instagram-cli post-feed --account-id <id> --file <png> (repeat) --caption "..."`
- `threads-cli publish-post --account-id <id> --media-item '{"file":"/abs/path"}' --text "..."`;
  chain replies with `--reply-to-post-fbid <previous post id>`. Media paths
  must be absolute. The publish output URL (threads.net/t/...) does NOT
  open the post; resolve the canonical URL with
  `threads-cli post --account-id <id> --post-id <id>` (field `url`).
- `facebook-cli pages posts create --page-id <id> --privacy PUBLIC --text "..." --file <png> (repeat)`;
  texts above ~1024 chars can be rejected, keep FB text under ±1000 chars.
- Threads/FB publishes may pop a user approval card on this platform;
  the run waits for the tap. That is expected, not a failure.
- None of the CLIs can delete or edit a published post. Deletion is a
  manual step in the platform app, and delete + repost is banned by the
  playbook anyway.
