import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const context = { URL, TextEncoder };
vm.runInNewContext(readFileSync(new URL('../browser-extension/reader.js', import.meta.url), 'utf8'), context);
const reader = context.CoucouReader;

test('restrict capture to real conversation origins and omit query/fragment', () => {
  assert.equal(reader.conversation('https://claude.ai/chat/abc?secret=x#frag').url, 'https://claude.ai/chat/abc');
  for (const url of ['https://claude.ai/', 'https://claude.ai/chat/', 'https://claude.ai.evil.test/chat/abc', 'https://user:password@claude.ai/chat/abc', 'https://claude.ai:8080/chat/abc', 'http://chatgpt.com/c/abc']) assert.equal(reader.conversation(url), null);
  assert.equal(reader.conversation('https://chatgpt.com/c/abc').provider, 'chatgpt');
});
test('take assistant responses only, keep entire text and ignore nested wrappers', () => {
  const inner = { innerText: 'Final response', contains: () => false };
  const outer = { innerText: 'Introduction\nFinal response', contains: node => node === inner };
  const earlier = { innerText: 'Earlier response', contains: () => false };
  let selector;
  const document = { querySelectorAll: value => { selector = value; return [earlier, outer, inner]; } };
  assert.equal(reader.latest(document, 'claude').text, 'Introduction\nFinal response');
  assert.match(selector, /assistant/);
  assert.equal(reader.latest({ querySelectorAll: () => [] }, 'chatgpt'), null);
  assert.equal(reader.latest({ querySelectorAll: () => [{ innerText: 'é'.repeat(100001), contains: () => false }] }, 'claude'), null);
});
test('never treat a recognized streaming response as finished', () => {
  assert.equal(reader.generating({ querySelector: () => ({}) }), true);
  assert.equal(reader.generating({ querySelector: () => null }), false);
});
