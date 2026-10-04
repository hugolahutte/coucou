const HOST = "fr.coucou.conversations";
const SPACES = new Set(["chatgptMac", "claudeCobra", "claudeHL"]);

function conversation(urlString) {
  try {
    const url = new URL(urlString);
    if (url.protocol !== "https:" || (url.port && url.port !== "443") || url.username || url.password) return null;
    const prefix = url.hostname === "claude.ai" ? "/chat/" : url.hostname === "chatgpt.com" ? "/c/" : null;
    const isChat = prefix && url.pathname.startsWith(prefix) && url.pathname.length > prefix.length;
    const isCowork = url.hostname === "claude.ai" && /^\/cowork\/cse_[A-Za-z0-9_-]+$/.test(url.pathname);
    if (!isChat && !isCowork) return null;
    return { key: `${url.origin}${url.pathname}`, id: url.pathname, provider: url.hostname === "claude.ai" ? "claude" : "chatgpt" };
  } catch { return null; }
}

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id) return false;
  const page = conversation(sender.url);
  if (!sender.tab || !page || sender.frameId !== 0) return false;
  (async () => {
    const key = `chat:${page.key}`;
    const config = (await chrome.storage.local.get(key))[key];
    if (message.type === "config") return { config: config || null };
    if (message.url !== page.key) throw new Error("La conversation a changé pendant la capture.");
    if (message.type !== "capture" || !config?.enabled || !SPACES.has(config.space)) throw new Error("Conversation non suivie.");
    if ((page.provider === "chatgpt") !== (config.space === "chatgptMac")) throw new Error("Compte incompatible avec ce site.");
    if (typeof message.text !== "string" || !message.text.trim() || new TextEncoder().encode(message.text).length > 200000) throw new Error("Réponse invalide ou trop longue.");
    if (typeof message.messageKey !== "string" || !message.messageKey || message.messageKey.length > 500) throw new Error("Identifiant de réponse invalide.");
    const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${message.messageKey}\n${message.text}`));
    const id = Array.from(new Uint8Array(bytes), b => b.toString(16).padStart(2, "0")).join("");
    const result = await chrome.runtime.sendNativeMessage(HOST, {
      coucou_kind: "conversation_response", space: config.space,
      conversation_id: page.id, url: page.key, title: config.title,
      message_id: id, text: message.text
    });
    if (!result?.ok) throw new Error(result?.error || "Coucou n’a pas enregistré cette réponse.");
    return { ok: true };
  })().then(respond, error => respond({ ok: false, error: error.message }));
  return true;
});
