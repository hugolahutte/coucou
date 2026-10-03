let page = CoucouReader.conversation(location.href);
let config = null;
let lastSaved = "";
let timer = null;
let capturing = false;
let candidate = "";
let stableSince = 0;

async function configure() {
  const next = CoucouReader.conversation(location.href);
  if (next?.id !== page?.id || next?.provider !== page?.provider) {
    page = next; lastSaved = ""; candidate = ""; stableSince = 0;
  }
  config = page ? (await chrome.runtime.sendMessage({ type: "config" }))?.config : null;
}

async function capture(manual = false) {
  if (capturing) return { ok: false, error: "Une capture est déjà en cours." };
  capturing = true;
  try {
    await configure();
    if (!config?.enabled || !page) return { ok: false, error: "Choisis d’abord le compte et active le suivi." };
    const capturedURL = page.url;
    if (CoucouReader.generating(document)) return { ok: false, error: "La réponse est encore en cours." };
    const reply = CoucouReader.latest(document, page.provider);
    if (!reply) return { ok: false, error: "Aucune réponse reconnue. Tu peux la copier et l’importer dans Coucou." };
    const signature = `${reply.messageKey}\n${reply.text}`;
    if (!manual) {
      if (signature !== candidate) { candidate = signature; stableSince = Date.now(); return; }
      if (Date.now() - stableSince < 5000 || signature === lastSaved) return;
    }
    const result = await chrome.runtime.sendMessage({ type: "capture", text: reply.text, messageKey: reply.messageKey, url: capturedURL });
    if (result?.ok) lastSaved = signature;
    return result;
  } finally { capturing = false; }
}

async function start() {
  await configure();
  if (timer) clearInterval(timer);
  timer = null;
  if (config?.enabled) timer = setInterval(() => { void capture().catch(() => {}); }, 3000);
}
chrome.storage.onChanged.addListener(() => { void start().catch(() => {}); });
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id) return false;
  if (message.type !== "capture-now") return false;
  capture(true).then(respond, error => respond({ ok: false, error: error.message }));
  return true;
});
void start().catch(() => {});
// Navigation between chats must drop the previous account binding before capture.
window.addEventListener("popstate", () => { void start().catch(() => {}); });
let lastURL = location.href;
new MutationObserver(() => {
  if (location.href !== lastURL) {
    lastURL = location.href;
    void start().catch(() => {});
  }
}).observe(document.documentElement, { childList: true, subtree: true });
