// Supabase Edge Function: save
// 1. Auth check -> insert URL -> respond immediately (capture stays instant)
// 2. In the background: fetch preview (no scraping — official oEmbed / Microlink),
//    then ask Claude which collection it belongs to.

import { createClient } from "npm:@supabase/supabase-js@2";

// Categories aren't hard-coded here — they're the rows of the `collections`
// table, the same list shown (and edited) in the map's sidebar. Every link is
// filed into one of those existing categories; we never invent a new one (the
// user adds those by hand) and never fall back to a generic Inbox bucket.

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  if (req.headers.get("x-token") !== Deno.env.get("SAVE_TOKEN")) {
    return new Response("unauthorized", { status: 401 });
  }

  const { url, title } = await req.json();
  if (!url) return new Response("missing url", { status: 400 });

  // consumed:false on conflict too — re-saving something you'd read before
  // brings it back to Unread (otherwise the upsert kept consumed=true and it
  // stayed hidden). board is left alone so it doesn't yank Inspiration items.
  const { data, error } = await supabase
    .from("links")
    .upsert({ url, title, status: "pending", consumed: false }, { onConflict: "url" })
    .select()
    .single();

  if (error) return new Response(error.message, { status: 500 });

  // Respond now; enrich after. Capture is never blocked by slow lookups.
  EdgeRuntime.waitUntil(enrich(data));

  return new Response(JSON.stringify({ ok: true }), {
    headers: { "content-type": "application/json" },
  });
});

async function enrich(link: { id: string; url: string; title: string | null }) {
  const url = link.url;
  let title = link.title;
  let image: string | null = null;
  let description: string | null = null;

  try {
    const yt = url.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/)([\w-]{11})/);

    if (yt) {
      // YouTube: predictable thumbnail URL + official oEmbed for the title
      image = `https://img.youtube.com/vi/${yt[1]}/hqdefault.jpg`;
      const r = await fetch(
        `https://www.youtube.com/oembed?url=${encodeURIComponent(url)}&format=json`,
      );
      if (r.ok) title = (await r.json()).title;
    } else if (/(?:twitter\.com|x\.com)\/\w+\/status\/(\d+)/.test(url)) {
      // X: FixTweet gives us the real media — a photo, a video's thumbnail
      // (a screengrab), or an X Article's cover + title. Text-only is the
      // rare fallback.
      const id = url.match(/status\/(\d+)/)![1];
      const r = await fetch(`https://api.fxtwitter.com/status/${id}`, {
        headers: { "user-agent": "Trove/1.0" },
      });
      if (r.ok) {
        const t = (await r.json())?.tweet ?? {};
        const media = t.media ?? {};
        const article = t.article ?? null;
        image =
          media.photos?.[0]?.url ??
          media.videos?.[0]?.thumbnail_url ??
          article?.cover_media?.media_info?.original_img_url ??
          null;
        const tweetText = (t.text ?? "").replace(/https?:\/\/t\.co\/\S+/g, "").replace(/\s+/g, " ").trim();
        title = article?.title ?? (tweetText || t.author?.name || title);
        description = t.author?.name ?? null;
      }
    } else {
      // Substack, LinkedIn, everything else: Microlink preview API
      // (LinkedIn will sometimes come back thin — the card falls back gracefully)
      const r = await fetch(`https://api.microlink.io/?url=${encodeURIComponent(url)}`);
      if (r.ok) {
        const j = await r.json();
        title = j.data?.title ?? title;
        image = j.data?.image?.url ?? null;
        description = j.data?.description ?? null;
      }
    }
  } catch (_) { /* preview is best-effort; the link is already safe */ }

  const collection = await categorize(title ?? url, description);

  await supabase
    .from("links")
    .update({ title, image, description, collection, status: "ready" })
    .eq("id", link.id);
}

async function categorize(title: string, description: string | null): Promise<string> {
  // The live category list — same rows the sidebar shows, in sidebar order.
  const { data: cols } = await supabase
    .from("collections")
    .select("name")
    .order("position", { ascending: true });
  const names = (cols ?? []).map((c) => c.name as string).filter(Boolean);
  if (names.length === 0) return "Inbox";     // no categories exist yet — nothing to file into
  const fallback = names[0];                  // best guess when the model is unsure / unreachable

  try {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 20,
        messages: [{
          role: "user",
          content:
            `Assign this saved link to exactly one of these existing categories: ${names.join(", ")}. ` +
            `You must choose one — even if the fit isn't perfect, pick the single most relevant. ` +
            `Do not invent a new category. Respond with the category name only, exactly as written above.\n\n` +
            `Title: ${title}\nContext: ${description ?? "(none)"}`,
        }],
      }),
    });
    const j = await r.json();
    const out = (j.content?.[0]?.text ?? "").trim();
    return names.find((n) => n === out)
        ?? names.find((n) => n.toLowerCase() === out.toLowerCase())
        ?? fallback;
  } catch {
    return fallback;
  }
}
