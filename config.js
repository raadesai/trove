// Trove — web-app config. Fill in your own Supabase project's values
// (Supabase dashboard → Project Settings → API).
//
// The anon key is PUBLIC by design — it ships to every browser. Row-Level
// Security (see supabase/schema.sql) is what keeps it safe: the anon role can
// only read links and edit a few curation columns, never write titles/images.
window.TROVE_CONFIG = {
  SUPABASE_URL:  "https://YOUR_PROJECT_REF.supabase.co",
  SUPABASE_ANON: "YOUR_SUPABASE_ANON_KEY",
  NAME:          "My Trove",   // shown as the name of your "inspiration" board
};
