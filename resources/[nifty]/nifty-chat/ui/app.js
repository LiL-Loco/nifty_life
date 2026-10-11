// Nifty Life 2.0 — chat UI.
//
// Presentation only. Whether a message may be sent, how long it may be, who hears
// it and who it is from are all answered in server/sv_chat.lua. Nothing here is a
// rule; this file draws what the server decided and forwards what the player typed.

const { nui, $ } = Nifty;

// Two purely visual values. Deliberately NOT in the settings table: they are read
// only by this browser, and a server-side tunable for them would be a second source
// of truth about numbers the server never sees. Everything the SERVER needs to
// enforce — max length, cooldown, radius — lives in `settings` (ADR-0009).
const CHAT_MAX_LINES = 12;
const CHAT_LINE_MS = 30000;

const state = { open: false };

function chatAddLine(line) {
  const log = $('chatLog');
  if (!log) return;

  const el = document.createElement('div');
  el.className = 'chat-line';

  if (line.system) {
    el.classList.add('chat-line--system');
    el.textContent = line.text || '';
  } else {
    // Built with textContent, never innerHTML. A chat message is player input;
    // putting it into innerHTML would make every other player a stored-XSS vector
    // against the machine running the server.
    const author = document.createElement('span');
    author.className = 'chat-line__author';
    author.textContent = line.author || '?';

    el.appendChild(author);
    el.appendChild(document.createTextNode(': ' + (line.text || '')));
  }

  log.appendChild(el);

  // Trim from the front, and cancel the timer of the line that goes, or it fires
  // against a detached node for no reason.
  while (log.children.length > CHAT_MAX_LINES) {
    const oldest = log.firstElementChild;
    if (!oldest) break;
    clearTimeout(Number(oldest.dataset.timer || 0));
    log.removeChild(oldest);
  }

  // Per-line expiry. A single timer for the whole log would make a five-minute-old
  // line vanish the moment a new message arrived, and a chat that forgets is worse
  // than a chat that scrolls.
  const timer = setTimeout(() => {
    el.classList.add('is-leaving');
    setTimeout(() => el.remove(), 650);
  }, CHAT_LINE_MS);
  el.dataset.timer = String(timer);
}

function openInput() {
  if (state.open) return;

  const box = $('chatInput');
  const field = $('chatField');
  if (!box || !field) return;

  state.open = true;
  box.classList.remove('hidden');
  field.value = '';
  field.focus();
}

/**
 * Close and tell the server to release the keyboard.
 *
 * The release is a server round trip, not a local state change: focus belongs to
 * Lua, and a client that only hid its own box would leave the cursor captured.
 * That is the most common FiveM UI bug and the reason this path is not a one-liner.
 *
 * `sendText` is read HERE, not in the message handler below. By the time the NUI
 * acknowledged the callback the field would already be hidden and its value is the
 * one thing in this UI that is not in a variable.
 */
function closeInput(sendText) {
  if (!state.open) return;

  const field = $('chatField');
  const text = sendText && field ? field.value.trim() : '';

  state.open = false;
  const box = $('chatInput');
  if (box) box.classList.add('hidden');

  nui(sendText ? 'chatSend' : 'chatCancel', { text });

  if (sendText && text !== '') {
    // Echo locally and immediately. Waiting for the server round trip makes the chat
    // feel broken at exactly the moment somebody is trying to talk during something
    // urgent. The server decides what is actually broadcast — this is a
    // convenience, not an echo the server approved.
    chatAddLine({ author: 'Du', text });
  }
}

window.addEventListener('message', (event) => {
  const { action, data } = event.data || {};
  if (!action) return;

  if (action === 'chatLine') {
    chatAddLine(data);
    return;
  }

  if (action === 'chatSystem') {
    chatAddLine({ system: true, text: data.text });
    return;
  }

  if (action === 'chatInput') {
    if (data.open) {
      openInput();
    } else {
      // The server closed us — focus was taken by another surface. Drop our state
      // without telling Lua, because Lua is the one that closed us; calling back
      // would release a keyboard this resource no longer holds, which is a no-op
      // the broker ignores. Doing it through closeInput() here would be theatre.
      state.open = false;
      const box = $('chatInput');
      if (box) box.classList.add('hidden');
    }
  }
});

(function wireChat() {
  const field = $('chatField');
  if (!field) return;

  field.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      closeInput(true);
    } else if (e.key === 'Escape') {
      e.preventDefault();
      closeInput(false);
    }
  });

  // Losing focus with text in the box would otherwise leave the NUI holding focus
  // over a hidden input. Cancel, do not send: an accidental click must never put a
  // half-typed sentence into the world.
  window.addEventListener('blur', () => {
    if (state.open) closeInput(false);
  });
})();