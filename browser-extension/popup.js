const status = document.querySelector("#status");
const space = document.querySelector("#space");
const title = document.querySelector("#title");
let tab, page;

async function init() {
  [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  page = CoucouReader.conversation(tab?.url);
  if (!page) throw new Error("Ouvre une conversation Claude ou ChatGPT.");
  const config = (await chrome.storage.local.get(`chat:${page.url}`))[`chat:${page.url}`];
  space.value = config?.space || (page.provider === "claude" ? "claudeHL" : "chatgptMac");
  for (const option of space.options) option.disabled = (page.provider === "chatgpt") !== (option.value === "chatgptMac");
  title.value = config?.title || (tab.title || "Conversation").slice(0, 300);
  status.textContent = config?.enabled ? "Suivi activé pour cette conversation." : "Suivi désactivé.";
}
function action(id, callback) {
  document.querySelector(id).addEventListener("click", () => {
    void callback().catch(error => { status.textContent = error.message; });
  });
}
action("#enable", async () => {
  if (!page || !title.value.trim()) throw new Error("Choisis une conversation et un nom.");
  await chrome.storage.local.set({ [`chat:${page.url}`]: { enabled: true, space: space.value, title: title.value.trim() } });
  status.textContent = "Suivi activé. Les nouvelles réponses seront ajoutées à ta liste.";
});
action("#disable", async () => {
  if (!page) return;
  await chrome.storage.local.remove(`chat:${page.url}`);
  status.textContent = "Suivi arrêté.";
});
action("#capture", async () => {
  if (!page) throw new Error("Ouvre une conversation.");
  const result = await chrome.tabs.sendMessage(tab.id, { type: "capture-now" });
  status.textContent = result?.ok ? "Réponse enregistrée dans Coucou." : result?.error || "Capture impossible.";
});
void init().catch(error => {
  status.textContent = error.message;
  document.querySelectorAll("button").forEach(button => { button.disabled = true; });
});
