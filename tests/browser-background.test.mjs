import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { webcrypto } from 'node:crypto';
import vm from 'node:vm';

function setup() {
  let listener;
  const sent = [];
  const config = { enabled: true, space: 'claudeHL', title: 'HL example' };
  const chrome = {
    runtime: { id: 'our-extension', onMessage: { addListener: value => { listener = value; } },
      sendNativeMessage: async (host, payload) => { sent.push({ host, payload }); return { ok: true }; } },
    storage: { local: { get: async key => ({ [key]: config }) } }
  };
  vm.runInNewContext(readFileSync(new URL('../browser-extension/background.js', import.meta.url), 'utf8'), { chrome, URL, TextEncoder, crypto: webcrypto });
  const sender = { id: 'our-extension', tab: { id: 7 }, frameId: 0, url: 'https://claude.ai/chat/abc' };
  const call = message => new Promise(resolve => { const handled = listener({ messageKey: 'assistant:1', ...message }, sender, resolve); if (!handled) resolve(null); });
  return { sent, config, sender, call };
}

test('native capture preserves account and conversation and strips caller fields', async () => {
  const { sent, call } = setup();
  assert.equal((await call({ type: 'capture', url: 'https://claude.ai/chat/abc', text: 'Final response', space: 'claudeCobra', command: 'do not run' })).ok, true);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].payload.space, 'claudeHL');
  assert.equal(sent[0].payload.conversation_id, '/chat/abc');
  assert.equal(sent[0].payload.command, undefined);
  assert.match(sent[0].payload.message_id, /^[0-9a-f]{64}$/);
});
test('navigation during capture cannot attach an old response to a new chat', async () => {
  const { sent, call } = setup();
  assert.equal((await call({ type: 'capture', url: 'https://claude.ai/chat/other', text: 'Old response' })).ok, false);
  assert.equal(sent.length, 0);
});
test('identical text from two distinct messages does not collapse into one reply', async () => {
  const { sent, call } = setup();
  await call({ type: 'capture', url: 'https://claude.ai/chat/abc', messageKey: 'assistant:1', text: 'Okay' });
  await call({ type: 'capture', url: 'https://claude.ai/chat/abc', messageKey: 'assistant:2', text: 'Okay' });
  assert.notEqual(sent[0].payload.message_id, sent[1].payload.message_id);
});
test('reject disabled tracking, mismatched provider and oversized response', async () => {
  const { sent, config, call } = setup();
  config.enabled = false;
  assert.equal((await call({ type: 'capture', url: 'https://claude.ai/chat/abc', text: 'Response' })).ok, false);
  config.enabled = true; config.space = 'chatgptMac';
  assert.equal((await call({ type: 'capture', url: 'https://claude.ai/chat/abc', text: 'Response' })).ok, false);
  config.space = 'claudeHL';
  assert.equal((await call({ type: 'capture', url: 'https://claude.ai/chat/abc', text: 'é'.repeat(100001) })).ok, false);
  assert.equal(sent.length, 0);
});
test('ignore foreign extensions, origins and nested frames', async () => {
  const { sent, sender, call } = setup();
  sender.id = 'foreign';
  assert.equal(await call({ type: 'capture', text: 'Response' }), null);
  sender.id = 'our-extension'; sender.url = 'https://evil.test/chat/abc';
  assert.equal(await call({ type: 'capture', text: 'Response' }), null);
  sender.url = 'https://claude.ai/chat/abc'; sender.frameId = 1;
  assert.equal(await call({ type: 'capture', text: 'Response' }), null);
  assert.equal(sent.length, 0);
});

test('Cowork uses the same validated native delivery as classic chats', async () => {
  const { sent, sender, call } = setup();
  sender.url = 'https://claude.ai/cowork/cse_01abc';
  assert.equal((await call({ type: 'capture', url: sender.url, text: 'Finished Cowork response' })).ok, true);
  assert.equal(sent[0].payload.conversation_id, '/cowork/cse_01abc');
  sender.url = 'https://claude.ai/cowork/projects';
  assert.equal(await call({ type: 'capture', url: sender.url, text: 'Project text' }), null);
  assert.equal(sent.length, 1);
});
