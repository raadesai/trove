// Endpoint + token live in secrets.js (gitignored — copy secrets.example.js and fill in).
importScripts("secrets.js");
const ENDPOINT = self.TROVE_ENDPOINT;
const TOKEN    = self.TROVE_TOKEN;

async function save(tab) {
  if (!tab || !tab.url || !/^https?:/.test(tab.url)) return;
  try {
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "content-type": "application/json", "x-token": TOKEN },
      body: JSON.stringify({ url: tab.url, title: tab.title || null }),
    });
    flash(tab.id, res.ok);
  } catch {
    flash(tab.id, false);
  }
}

// Badge on the toolbar icon: green tick = saved, red ! = failed
function flash(tabId, ok) {
  chrome.action.setBadgeText({ text: ok ? "✓" : "!", tabId });
  chrome.action.setBadgeBackgroundColor({ color: ok ? "#2F5B40" : "#B3402A", tabId });
  setTimeout(() => chrome.action.setBadgeText({ text: "", tabId }), 1800);
}

// Click the toolbar icon
chrome.action.onClicked.addListener(save);

// Cmd+Shift+S / Ctrl+Shift+S
chrome.commands.onCommand.addListener(async (cmd) => {
  if (cmd !== "save-link") return;
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  save(tab);
});
