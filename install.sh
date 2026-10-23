#!/usr/bin/env bash
# homeless-media-automation installer
#
# Installs the Homeless Media daily AI-news automation (scout -> filter ->
# writer -> designer -> post IG/Threads/FB [+ blog]) into a content workspace
# on this machine. Idempotent: re-running refreshes the code payload and the
# venv, and NEVER overwrites runtime state (news.db, posted.log, learnings.md,
# trending.md, engagement-playbook.md, out/, work/).
#
# Usage:
#   bash install.sh                     # uses ./hm.config.json (created from the example on first run)
#   bash install.sh path/to/config.json
#   HM_CONFIG=path/to/config.json bash install.sh
#
# After install, open <content_dir>/SETUP-CRON.md and ask Muse on this
# machine to create the daily cron from it. That is the only manual step
# besides connecting the social accounts (see README.md).
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${1:-${HM_CONFIG:-$PKG_DIR/hm.config.json}}"

say()  { printf '\n== %s\n' "$*"; }
warn() { printf '   [warn] %s\n' "$*"; }
ok()   { printf '   [ ok ] %s\n' "$*"; }

# ---------------------------------------------------------------- config ---
if [ ! -f "$CONFIG" ]; then
  cp "$PKG_DIR/config/hm.config.example.json" "$CONFIG"
  say "Config created: $CONFIG"
  echo "   Edit it first (brand, handles, account IDs, content_dir, blog),"
  echo "   then re-run: bash install.sh \"$CONFIG\""
  exit 0
fi

say "Reading config: $CONFIG"
set -a
eval "$(python3 - "$CONFIG" <<'PYEOF'
import json, shlex, sys
c = json.load(open(sys.argv[1]))
def g(path, default=""):
    cur = c
    for k in path.split("."):
        cur = cur.get(k, default) if isinstance(cur, dict) else default
    return cur
vals = {
    "BRAND_NAME": g("brand_name"), "BRAND_LABEL": g("brand_label"),
    "HANDLE": g("handle"), "COMMUNITY_URL": g("community_url"),
    "FOOTER_TEXT": g("footer_text", "GABUNG KE KOMUNITAS KAMI"),
    "CONTENT_DIR": g("content_dir"), "TIMEZONE": g("timezone", "Asia/Jakarta"),
    "SCHEDULE_TIME": g("schedule_time", "09:36"),
    "CRON_TITLE": g("cron_title", "Homeless Media daily AI news"),
    "IG_ID": g("accounts.instagram_id"), "THREADS_ID": g("accounts.threads_id"),
    "FB_ID": g("accounts.facebook_page_id"),
    "BLOG_ENABLED": "true" if g("blog.enabled", False) else "false",
    "BLOG_URL": g("blog.base_url"), "MASCOT_SRC": g("mascot_path"),
}
for k, v in vals.items():
    print(f"{k}={shlex.quote(str(v))}")
PYEOF
)"
set +a

[ -n "$CONTENT_DIR" ] || { echo "content_dir is empty in config"; exit 1; }
case "$IG_ID$THREADS_ID$FB_ID" in *ISI_*) warn "Account IDs still contain placeholders (ISI_...). Code install can continue; fill real IDs in the config and re-run before creating the cron.";; esac

# ------------------------------------------------------------ preflight ----
say "Preflight"
command -v python3 >/dev/null || { echo "python3 not found"; exit 1; }
python3 -c "import sys; assert sys.version_info >= (3, 9), sys.version" \
  || { echo "python3 >= 3.9 required"; exit 1; }
ok "python3 $(python3 -V 2>&1 | awk '{print $2}')"
if [ -f /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf ]; then
  ok "DejaVu fonts present (designer requirement)"
else
  warn "DejaVu fonts missing. Install: sudo apt install -y fonts-dejavu (designer will fail without them)"
fi
for cli in instagram-cli threads-cli facebook-cli; do
  if [ -x "/opt/hatch/bin/$cli" ]; then ok "$cli present"; else warn "$cli not found at /opt/hatch/bin (needed at posting time; connect the accounts in Muse first)"; fi
done

# --------------------------------------------------------------- layout ----
say "Creating workspace layout at $CONTENT_DIR"
mkdir -p "$CONTENT_DIR/hm/out" "$CONTENT_DIR/hm/visuals" "$CONTENT_DIR/hm/work" \
         "$CONTENT_DIR/hm/review" "$CONTENT_DIR/blog" "$CONTENT_DIR/images" \
         "$CONTENT_DIR/assets"
touch "$CONTENT_DIR/posted.log"
for t in engagement-playbook.md learnings.md trending.md; do
  if [ ! -f "$CONTENT_DIR/$t" ]; then
    cp "$PKG_DIR/payload/templates/$t" "$CONTENT_DIR/$t"; ok "seeded $t"
  else
    ok "kept existing $t"
  fi
done

# ------------------------------------------------------------ code payload -
say "Installing pipeline code"
cp "$PKG_DIR/payload/hm/scout.py" "$PKG_DIR/payload/hm/filter.py" \
   "$PKG_DIR/payload/hm/designer.py" "$PKG_DIR/payload/hm/requirements.txt" \
   "$CONTENT_DIR/hm/"
cp "$PKG_DIR/payload/hm/README.md" "$CONTENT_DIR/hm/README.md"

DB_PATH="$CONTENT_DIR/hm/news.db"
sed -i "s|/home/hatch/workspace/peka-content/hm/news.db|$DB_PATH|g" \
  "$CONTENT_DIR/hm/scout.py" "$CONTENT_DIR/hm/filter.py"
sed -i -e "s|Peka Homeless Media|Homeless Media|g" -e "s|PekaHM/1.0|HomelessMedia/1.0|g" \
  "$CONTENT_DIR/hm/scout.py" "$CONTENT_DIR/hm/filter.py"

BRAND_UPPER="$(printf '%s' "$BRAND_NAME" | tr '[:lower:]' '[:upper:]')"
sed -i \
  -e "s|/home/hatch/workspace/peka-logo/mascot-p.png|$CONTENT_DIR/assets/mascot.png|g" \
  -e "s|Peka Homeless Media|Homeless Media|g" \
  -e "s|Peka header|Brand header|g" \
  -e "s|@peka\.ai\.id|@$HANDLE|g" \
  -e "s|URL\.PEKA\.AI\.ID|$COMMUNITY_URL|g" \
  -e "s|peka\.ai\.id|$BRAND_LABEL|g" \
  -e "s|PEKA AI NEWS|$BRAND_UPPER NEWS|g" \
  -e "s|PEKA NEWS|$BRAND_UPPER NEWS|g" \
  -e "s|GABUNG KE KOMUNITAS KAMI|$FOOTER_TEXT|g" \
  "$CONTENT_DIR/hm/designer.py"
if grep -qi "peka" "$CONTENT_DIR/hm/designer.py"; then
  warn "designer.py still contains 'peka' strings (probably comments only):"
  grep -in "peka" "$CONTENT_DIR/hm/designer.py" | head -5 | sed 's/^/     /'
fi
ok "patched DB path + brand strings (label=$BRAND_LABEL, handle=@$HANDLE)"

# ---------------------------------------------------------------- mascot ---
say "Brand mascot"
if [ -n "$MASCOT_SRC" ]; then
  case "$MASCOT_SRC" in /*) SRC="$MASCOT_SRC";; *) SRC="$PKG_DIR/$MASCOT_SRC";; esac
  cp "$SRC" "$CONTENT_DIR/assets/mascot.png"; ok "copied mascot from $SRC"
elif [ -f "$CONTENT_DIR/assets/mascot.png" ]; then
  ok "kept existing assets/mascot.png"
else
  warn "no mascot configured; generating a placeholder (replace assets/mascot.png with the real one anytime)"
  CONTENT_DIR="$CONTENT_DIR" BRAND_NAME="$BRAND_NAME" python3 - <<'PYEOF'
import os
from PIL import Image, ImageDraw, ImageFont
d = os.environ["CONTENT_DIR"]; letter = (os.environ.get("BRAND_NAME") or "M")[:1].upper()
img = Image.new("RGB", (512, 512), (0, 0, 0))
dr = ImageDraw.Draw(img)
try:
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 340)
except Exception:
    f = ImageFont.load_default()
box = dr.textbbox((0, 0), letter, font=f)
w, h = box[2] - box[0], box[3] - box[1]
dr.text(((512 - w) / 2 - box[0], (512 - h) / 2 - box[1]), letter, font=f, fill=(255, 214, 10))
img.save(os.path.join(d, "assets", "mascot.png"))
print("   placeholder mascot written")
PYEOF
fi

# ------------------------------------------------------------------ venv ---
say "Python venv (feedparser + Pillow)"
if [ ! -x "$CONTENT_DIR/hm/venv/bin/python" ]; then
  python3 -m venv "$CONTENT_DIR/hm/venv"
fi
"$CONTENT_DIR/hm/venv/bin/pip" install -q --disable-pip-version-check -r "$CONTENT_DIR/hm/requirements.txt"
"$CONTENT_DIR/hm/venv/bin/python" -c "import feedparser, PIL; print('   [ ok ] feedparser + Pillow import cleanly')"

# --------------------------------------------------------------- news.db ---
say "News database"
if [ ! -f "$DB_PATH" ]; then
  (cd "$CONTENT_DIR/hm" && ./venv/bin/python scout.py --test) || warn "feed self-test failed (network?); DB will initialise on the first cron run"
  (cd "$CONTENT_DIR/hm" && ./venv/bin/python scout.py) || warn "initial scout run failed; the cron retries daily anyway"
else
  ok "kept existing news.db"
fi

# ------------------------------------------------------------ smoke test ---
say "Designer smoke test"
python3 - <<'PYEOF'
from PIL import Image, ImageDraw
img = Image.new("RGB", (1600, 1600), (12, 14, 20))
d = ImageDraw.Draw(img)
for i in range(0, 1600, 80):
    d.line([(i, 1600), (1600, 1600 - i)], fill=(40, 44, 60), width=3)
d.ellipse([1050, 180, 1420, 550], outline=(255, 214, 10), width=10)
img.save("/tmp/hm-smoke-visual.png")
PYEOF
"$CONTENT_DIR/hm/venv/bin/python" "$CONTENT_DIR/hm/designer.py" \
  --out "$CONTENT_DIR/hm/out/smoke-test" --badge "AI NEWS" \
  --headline "Smoke test: designer berjalan di mesin ini" \
  --sub "Carousel contoh hasil installer homeless-media-automation" \
  --points "Scout menarik RSS AI tiap pagi|Filter memberi skor viral|Designer merakit carousel 2K|Cron memposting ke IG, Threads, FB" \
  --source "Installer" --url "https://example.com" \
  --visual /tmp/hm-smoke-visual.png --theme auto >/dev/null
ls "$CONTENT_DIR/hm/out/smoke-test/"*.png >/dev/null 2>&1 \
  && ok "smoke carousel rendered: $CONTENT_DIR/hm/out/smoke-test/" \
  || { echo "designer smoke test FAILED"; exit 1; }

# -------------------------------------------------------------- cron body --
say "Rendering cron body"
python3 - "$PKG_DIR/payload/cron/hm-daily.cron.md" "$CONTENT_DIR/SETUP-CRON.md" <<'PYEOF'
import os, sys
tpl = open(sys.argv[1]).read()
blog = os.environ.get("BLOG_ENABLED") == "true"
rep = {
    "{{BRAND_NAME}}": os.environ["BRAND_NAME"], "{{HANDLE}}": os.environ["HANDLE"],
    "{{CONTENT_DIR}}": os.environ["CONTENT_DIR"], "{{IG_ACCOUNT_ID}}": os.environ["IG_ID"],
    "{{THREADS_ACCOUNT_ID}}": os.environ["THREADS_ID"], "{{FB_PAGE_ID}}": os.environ["FB_ID"],
    "{{BLOG_CLAUSE}}": " + blog" if blog else "",
    "{{BLOG_MENTION}}": " di blog" if blog else "",
    "{{BLOG_ANGLE}}": ", dan jadi satu subjudul praktis di blog" if blog else "",
    "{{BLOG_REPORT}}": " + blog" if blog else "",
}
if blog:
    rep["{{BLOG_SPEC}}"] = ('Blog SANGAT LENGKAP: body_html berupa artikel utuh 800-1200 kata: paragraf pembuka '
        '(ringkasan berita + kenapa penting), beberapa subjudul <h3> per aspek (latar belakang, detail utama, '
        'dampak dan reaksi, apa selanjutnya), paragraf penutup, dan baris sumber berisi link artikel aslinya. '
        'Semua isi dari fakta sumber, JANGAN ngarang. Blog JSON: {"slug","title","date","datetime","excerpt",'
        '"image","images":[...],"body_html","tags":["AI",...],"links":{"instagram":"","threads":"","facebook":""}} '
        '— field "images" berisi nama file SEMUA slide carousel secara berurutan (diisi di langkah 8); tags 1-3 label.')
    rep["{{BLOG_STEP}}"] = ('BLOG: salin SEMUA slide carousel ke ' + os.environ["CONTENT_DIR"] + '/images/: slide pertama '
        'menjadi hm-<slug>.png, berikutnya hm-<slug>-2.png, hm-<slug>-3.png, dst. Tulis ' + os.environ["CONTENT_DIR"] +
        '/blog/<slug>.json (body_html dari langkah 4) dengan image=hm-<slug>.png, "images"=[semua file slide itu '
        'berurutan], links terisi URL postingan. Verifikasi ' + os.environ.get("BLOG_URL", "") + '/p/<slug> return 200.')
else:
    rep["{{BLOG_SPEC}}"] = "(Blog nonaktif di konfigurasi instalasi ini: lewati keluaran blog.)"
    rep["{{BLOG_STEP}}"] = "(Blog nonaktif: lewati langkah ini.)"
for k, v in rep.items():
    tpl = tpl.replace(k, v)
open(sys.argv[2], "w").write(tpl)
print("   [ ok ] cron body rendered")
PYEOF

# ---------------------------------------------------------------- summary --
say "INSTALL COMPLETE"
cat <<EOF
   Workspace : $CONTENT_DIR
   Pipeline  : $CONTENT_DIR/hm/ (scout.py, filter.py, designer.py, news.db)
   Cron body : $CONTENT_DIR/SETUP-CRON.md
   Smoke test: $CONTENT_DIR/hm/out/smoke-test/ (open the PNGs, check the header lockup)

   Remaining manual steps (full detail in README.md):
   1. Connect the brand's Instagram, Threads and Facebook in Muse on this
      machine, and put the real account IDs in $CONFIG
      (accounts.instagram_id / threads_id / facebook_page_id), then re-run
      this installer so SETUP-CRON.md picks them up.
   2. Replace $CONTENT_DIR/assets/mascot.png with the real brand mascot
      (black background, it is chroma-keyed by the designer).
   3. Ask Muse here: "create the daily cron from $CONTENT_DIR/SETUP-CRON.md"
      with schedule: daily at $SCHEDULE_TIME ($TIMEZONE), title "$CRON_TITLE".
   4. First run: watch the approval cards (Threads/FB posting asks for a tap
      per publish on this platform) and verify the report links.
EOF
