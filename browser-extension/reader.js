/* Isolated content-script world. Never reads cookies, tokens or page scripts. */
globalThis.CoucouReader = {
  conversation(urlString) {
    try {
      const url = new URL(urlString);
      if (url.protocol !== "https:" || url.username || url.password || (url.port && url.port !== "443")) return null;
      const prefix = url.hostname === "claude.ai" ? "/chat/" : url.hostname === "chatgpt.com" ? "/c/" : null;
      if (!prefix || !url.pathname.startsWith(prefix) || url.pathname.length <= prefix.length) return null;
      return { id: url.pathname, url: `${url.origin}${url.pathname}`, provider: url.hostname === "claude.ai" ? "claude" : "chatgpt" };
    } catch { return null; }
  },
  latest(document, provider) {
    const selectors = provider === "chatgpt"
      ? '[data-message-author-role="assistant"]'
      : '[data-message-author-role="assistant"], .font-claude-response';
    const elements = Array.from(document.querySelectorAll(selectors));
    // Claude's wrapper may carry both selectors: keep outer responses only.
    const responses = elements.filter((node) => !elements.some((other) => other !== node && other.contains(node)));
    const last = responses.at(-1);
    if (!last) return null;
    const text = (last.innerText || "").trim();
    if (!text || new TextEncoder().encode(text).length > 200000) return null;
    const explicitID = last.getAttribute?.("data-message-id") || last.closest?.("[data-message-id]")?.getAttribute("data-message-id");
    return { text, messageKey: explicitID ? `message:${explicitID}` : `assistant:${responses.length - 1}` };
  },
  generating(document) {
    return Boolean(document.querySelector('[data-is-streaming="true"], [data-message-streaming="true"], button[aria-label="Stop generating"], button[aria-label="Stop response"], button[aria-label="Arrêter la génération"], button[aria-label="Arrêter la réponse"]'));
  }
};
