# Trove — one-click link saver → visual map

Save any tab with one click (or ⌘⇧S). It lands on your **map** — previewed and
auto-filed into a collection by Claude. No scraping: previews come from official
oEmbed endpoints (YouTube, X) and the Microlink preview API (Substack + the
rest). Everything runs on free tiers; the only cost is a fraction of a cent per
save for the Haiku categorisation call.

Three pieces, set up in this order:

1. **Supabase** — the database + a `save` edge function (the backend).
2. **The map** (`index.html`) — a static page that reads your links.
3. **A saver** — a Chrome extension (⌘⇧S) and/or an optional macOS double-tap-fn
   hotkey.

## 1. Supabase (~5 min)

1. Create a project at [supabase.com](https://supabase.com) (free tier is fine).
2. SQL Editor → paste and run [`supabase/schema.sql`](supabase/schema.sql). This
   creates the `links` and `collections` tables and the row-level security that
   makes the anon key safe to expose (it can read links and edit a few curation
   columns, nothing else).
3. Install the [Supabase CLI](https://supabase.com/docs/guides/cli), then from
   this folder:
   ```bash
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   supabase secrets set SAVE_TOKEN=some-long-random-string
   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
   supabase functions deploy save --no-verify-jwt
   ```
   (`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided to the function
   automatically.) `SAVE_TOKEN` is the shared secret your savers send to prove a
   request is yours; `ANTHROPIC_API_KEY` powers the auto-filing.

## 2. The map (`index.html`)

1. Open [`config.js`](config.js) and fill in your Supabase **URL** and **anon
   key** (Project Settings → API). The anon key is public by design — see the
   note in that file.
2. Serve the folder over HTTP — e.g. `python3 -m http.server` then open
   <http://localhost:8000>. (Opening the file directly with `file://` won't load
   `config.js`.)

Collections are **rows in the `collections` table**, editable right in the map's
sidebar: double-click to rename, **+** to add, **×** to delete (its links move to
Inbox). The `save` function files each new link into one of your existing
collections — name them the way *you* think, not like a librarian.

### Deploy it (optional)

The map is a static page — deploy the folder to [Vercel](https://vercel.com/new),
Netlify, or GitHub Pages. `.vercelignore` already restricts a Vercel deploy to
just the web app (`index.html`, `config.js`, `wallpapers/`). Because `config.js`
holds only the public anon key, it's committed and ships with the deploy.

## 3. A saver

### Chrome extension (⌘⇧S)
1. Copy `extension/secrets.example.js` → `extension/secrets.js` (gitignored) and
   fill in `TROVE_ENDPOINT` (your `save` function URL,
   `https://YOUR_PROJECT_REF.supabase.co/functions/v1/save`) and `TROVE_TOKEN`
   (the `SAVE_TOKEN` from step 1).
2. Chrome → `chrome://extensions` → enable Developer mode → **Load unpacked** →
   pick the `extension/` folder. Pin the icon.
3. Check the hotkey at `chrome://extensions/shortcuts` (set ⌘⇧S / Ctrl⇧S for
   "Save current tab to Trove" if empty).
4. Test: on any YouTube video hit ⌘⇧S → green ✓ → the row appears on your map
   within ~10s, titled, previewed, and filed.

### Optional: double-tap fn to save (macOS)
Chrome extensions can't see the fn key, so this runs at the OS level via
[Karabiner-Elements](https://karabiner-elements.pqrs.org) (free), with an
optional [Hammerspoon](https://www.hammerspoon.org) paper-plane animation.

1. Put your config where the scripts can read it (never committed):
   ```bash
   mkdir -p ~/.config/trove
   cp mac-fn-hotkey/config.example ~/.config/trove/config   # then edit it
   ```
2. Place this repo at `~/trove` (or edit the path inside
   `mac-fn-hotkey/karabiner-trove.json`), and `chmod +x mac-fn-hotkey/save.sh`.
3. System Settings → Keyboard → "Press 🌐 key to" → **Do Nothing** (frees fn).
4. Copy `mac-fn-hotkey/karabiner-trove.json` into
   `~/.config/karabiner/assets/complex_modifications/`, then Karabiner → Complex
   Modifications → Add rule → enable "Double-tap fn".
5. (Optional animation) point Hammerspoon at `mac-fn-hotkey/hammerspoon-init.lua`
   and reload.
6. Grant Karabiner + your terminal the Automation permission for Chrome when
   macOS asks. Test: double-tap fn on any page → "Saved ✓".

If double-tap feels flaky, the extension's ⌘⇧S is the reliable path — keep both.

## Notes
- Re-saving the same URL updates the row instead of duplicating (unique index),
  and brings it back to Unread.
- LinkedIn previews are unreliable by design (they block preview services); those
  cards fall back to title-only and still look fine.

## License

MIT — see [LICENSE](LICENSE).
