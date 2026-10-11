// Nifty Life 2.0 — character creator UI.
//
// Presentation only (ADR-0011): this file renders options and forwards clicks
// to the Lua side. It never decides what an appearance is valid — the server
// validates and rebuilds that structure before storing it (ADR-0017).

const state = {
  open: false,
  model: 'mp_m_freemode_01',
  gender: 'male',
  slots: { components: {}, props: {} },
  collections: [],
  selection: { kind: 'components', id: 0, collection: '', drawable: 0, texture: 0 },
};

// Human-readable names for freemode slots. Slots without an entry fall back to
// their index, so a slot we have not named still works rather than hiding.
const COMPONENT_NAMES = {
  0: 'Kopfbedeckung', 1: 'Haare', 2: 'Brille', 3: 'Oberteil', 4: 'Hose',
  5: 'Schuhe', 6: 'Socken', 7: 'Jacke', 8: 'Unterhemd', 9: 'Krawatte',
  10: 'Kurze Hose', 11: 'Armband', 12: 'Kette',
};

const PROP_NAMES = {
  0: 'Mütze', 1: 'Brille', 2: 'Ohrring', 3: 'Uhr', 4: 'Armband',
  5: 'Ring', 12: 'Kette',
};

// PLACEHOLDER swatches. These are index chips, not the true in-game colours —
// the real palette needs verified per-component values. See launch gate v2.
const PLACEHOLDER_COLOURS = [
  '#1b1b1f', '#4a4d52', '#7a6a56', '#b9b5a6', '#e6e2d8', '#2c2e32',
  '#5a3a22', '#8c5a3c', '#c8a878', '#3d5a3d', '#2f5a6b', '#6b2f3d',
  '#4b3a6b', '#6b6b2f', '#a03d5a', '#3da08c', '#8c8c3d', '#5a3d8c',
  '#3d8ca0', '#a05a3d',
];

const $ = (id) => document.getElementById(id);

/**
 * Call a NUI callback on the Lua side.
 *
 * `https://`, not `http://`. The NUI page is served from
 * `https://cfx-nui-nifty-core/html/index.html`, so an `http://` request to the
 * resource is MIXED CONTENT: CEF blocks it before it leaves the browser and the
 * Lua callback never runs.
 *
 * This was not a typo nobody noticed — it was `http://` in the only fetch helper
 * in this file, so every NUI callback in the resource was blocked: the creator's
 * submit, the panels, and the phone. It surfaced only when `chat` was started and
 * its own mixed-content warning made somebody look at the scheme in the first
 * place. `SetNuiFocus` still behaves correctly on its own; the UI simply could
 * never have worked (see docs/vertical-slice.md, "No NUI frame has been rendered").
 */
async function nui(name, body) {
  const res = await fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(body || {}),
  });
  return res.json();
}

// ------------------------------------------------------------------ render

function renderSlotLists() {
  const build = (kind, containerId, names) => {
    const list = $(containerId);
    list.innerHTML = '';

    const slots = state.slots[kind];
    Object.keys(slots)
      .map(Number)
      .sort((a, b) => a - b)
      .forEach((id) => {
        const li = document.createElement('li');
        li.className = 'slotlist__item';
        if (state.selection.kind === kind && state.selection.id === id) {
          li.classList.add('is-active');
        }
        li.innerHTML =
          `<span>${names[id] || `Slot ${id}`}</span>` +
          `<span class="slotlist__index">${id}</span>`;

        li.addEventListener('click', () => {
          const first = state.slots[kind][String(id)];
          if (first) selectSlot(kind, id, first.collection);
        });

        list.appendChild(li);
      });
  };

  build('components', 'componentList', COMPONENT_NAMES);
  build('props', 'propList', PROP_NAMES);
}

function renderVariants() {
  const kind = state.selection.kind;
  const id = String(state.selection.id);
  const slots = state.slots[kind] || {};
  const slot = slots[id];

  $('variantsTitle').textContent =
    (kind === 'components' ? COMPONENT_NAMES[Number(id)] || `Komponente ${id}`
                           : PROP_NAMES[Number(id)] || `Prop ${id}`) +
    (slot ? '' : ' — keine Optionen');

  const grid = $('variantGrid');
  grid.innerHTML = '';

  if (!slot) return;

  const collections = slot.collections || {};
  Object.keys(collections)
    .sort()
    .forEach((collectionName) => {
      const count = collections[collectionName] || 0;
      for (let d = 0; d < count; d++) {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'variant';
        btn.textContent = d;
        btn.title = collectionName === '' ? 'Standard' : collectionName;

        if (collectionName === state.selection.collection &&
            d === state.selection.drawable) {
          btn.classList.add('is-active');
        }

        btn.addEventListener('click', () => {
          selectSlot(kind, Number(id), collectionName, d);
        });
        grid.appendChild(btn);
      }
    });

  renderColours();
}

function renderColours() {
  const grid = $('colourGrid');
  grid.innerHTML = '';

  PLACEHOLDER_COLOURS.forEach((colour, index) => {
    const chip = document.createElement('div');
    chip.className = 'colour';
    chip.style.background = colour;
    chip.title = `Farbe ${index}`;
    if (index === state.selection.texture) chip.classList.add('is-active');
    chip.addEventListener('click', () => {
      state.selection.texture = index;
      renderColours();
      pushSelection();
    });
    grid.appendChild(chip);
  });
}

function selectSlot(kind, id, collection, drawable) {
  state.selection.kind = kind;
  state.selection.id = id;
  state.selection.collection = collection ?? '';

  const slot = (state.slots[kind] || {})[String(id)];
  if (slot) {
    const first = (slot.collections || {})[state.selection.collection] || 1;
    state.selection.drawable = drawable ?? 0;
    state.selection.texture = 0;
    void first;
  }

  renderSlotLists();
  renderVariants();
  pushSelection();
}

function pushSelection() {
  const { kind, id, collection, drawable, texture } = state.selection;
  nui('creator:apply', {
    kind,
    id,
    collection,
    drawable,
    texture,
    model: state.model,
  });
}

// ------------------------------------------------------------------ forms

function wireForms() {
  $('gender').addEventListener('click', (e) => {
    const btn = e.target.closest('[data-gender]');
    if (!btn) return;
    state.gender = btn.dataset.gender;
    [...$('gender').children].forEach((b) => b.classList.remove('is-active'));
    btn.classList.add('is-active');
  });

  $('model').addEventListener('click', (e) => {
    const btn = e.target.closest('[data-model]');
    if (!btn) return;
    state.model = btn.dataset.model;
    [...$('model').children].forEach((b) => b.classList.remove('is-active'));
    btn.classList.add('is-active');
    // Changing model invalidates every collection/variant list.
    nui('creator:model', { model: state.model });
  });

  $('randomise').addEventListener('click', () => nui('creator:randomise', { model: state.model }));
  $('reset').addEventListener('click', () => nui('creator:reset', { model: state.model }));

  $('submit').addEventListener('click', async () => {
    const btn = $('submit');
    btn.disabled = true;
    $('error').classList.add('hidden');

    const result = await nui('creator:submit', {
      firstName: $('firstName').value.trim(),
      lastName: $('lastName').value.trim(),
      dateOfBirth: $('dateOfBirth').value,
      gender: state.gender,
      model: state.model,
    });

    if (result && result.ok) {
      $('creator').classList.add('hidden');
    } else {
      btn.disabled = false;
      const box = $('error');
      box.textContent = (result && result.error) || 'Unbekannter Fehler.';
      box.classList.remove('hidden');
    }
  });
}

// ----------------------------------------------------------------- events

window.addEventListener('message', (event) => {
  const msg = event.data;
  if (!msg || !msg.action) return;

  if (msg.action === 'close') {
    $('creator').classList.add('hidden');
    return;
  }

  if (msg.action === 'error') {
    // Server refused the character. Keep the form up so the player can fix it.
    const box = $('error');
    box.textContent = msg.message || 'Unbekannter Fehler.';
    box.classList.remove('hidden');
    $('submit').disabled = false;
    return;
  }

  if (msg.action !== 'open') return;

  state.open = true;
  state.model = msg.model || 'mp_m_freemode_01';
  state.slots = msg.slots || { components: {}, props: {} };
  state.collections = msg.collections || [];

  if (!Object.keys(state.slots.components || {}).length) {
    // Model arrived with no slot data yet — ask again shortly.
    setTimeout(() => nui('creator:slots', { model: state.model }), 400);
  }

  // reflect identity defaults coming from the server
  if (msg.gender) {
    state.gender = msg.gender;
    [...$('gender').children].forEach((b) =>
      b.classList.toggle('is-active', b.dataset.gender === msg.gender));
  }
  [...$('model').children].forEach((b) =>
    b.classList.toggle('is-active', b.dataset.model === state.model));

  $('error').classList.add('hidden');
  $('submit').disabled = false;

  renderSlotLists();
  renderVariants();

  const firstComponent = Object.keys(state.slots.components || {})[0];
  if (firstComponent) {
    selectSlot('components', Number(firstComponent),
      state.slots.components[firstComponent].collections
        ? Object.keys(state.slots.components[firstComponent].collections)[0] : '');
  }

  $('creator').classList.remove('hidden');
});

document.addEventListener('DOMContentLoaded', () => {
  wireForms();
  wireHud();
  wirePhone();
  $('creator').classList.add('hidden');
});

// ===========================================================================
// HUD and panels - the vertical slice surface.
//
// Same rule as the creator above (ADR-0011): this section renders what the
// server sent and forwards clicks. It never decides whether a purchase is
// affordable, a job can be joined, or an item exists. Every button here sends
// a code; the server answers with what actually happened.
// ===========================================================================

const hud = {
  money: { cash: 0, bank: 0 },
  inventory: { items: [], usedSlots: 0, totalSlots: 0, usedWeight: 0, maxWeight: 0 },
  // Character + appearance. Populated by nifty:client:enterWorld and
  // nifty:client:character. The inventory's OUTFIT section reads
  // hud.character.appearance and lists every worn component/prop.
  character: null,
  jobs: [],
  jobCatalogue: [],
  shop: [],
  properties: [],
  vehicles: [],
  panel: null,
};

// Per-character inventory UI settings. Persisted in localStorage under
// `nifty.inv.settings.v1`. The toggles let the player hide sections
// they don't want to look at, so a pickup-heavy session can clear
// the OUTFIT column and an outfit-driven player can collapse the
// BACKPACK column.
//
// These settings are owned by the inventory panel itself; they live in
// nifty-inventory/ui/app.js. nifty-world's panel builder calls them via
// the cross-script global window.__niftyInventory.panelInventory.

let toastTimer = null;

// German number formatting. Prices arrive as JSON numbers already rounded by
// the server to two decimals - this only lays them out, it never reformats a
// value back into something the server did not send.
const money = (n) => `${Number(n || 0).toLocaleString('de-DE', {
  minimumFractionDigits: 2, maximumFractionDigits: 2,
})} $`;

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function showToast(ok, message) {
  const toast = $('toast');
  if (!toast) return;

  toast.textContent = message || (ok ? 'Erledigt.' : 'Das hat nicht geklappt.');
  toast.classList.toggle('toast--error', !ok);
  toast.classList.remove('hidden');

  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.add('hidden'), 3500);
}

// Inventory panel renders via the cross-script global that nifty-inventory's
// app.js attached. Each call passes the live HUD snapshot so the inventory
// panel does not need its own reactive state.
function panelInventoryProxy() {
  if (window.__niftyInventory && window.__niftyInventory.panelInventory) {
    return window.__niftyInventory.panelInventory(hud);
  }
  // The script failed to load (offline CEF, blocked cfx-nui URL, etc.).
  // Surface a placeholder rather than crashing the page.
  const wrap = el('div', 'panel-shell__empty',
    'Inventar konnte nicht geladen werden.');
  return wrap;
}

function panelShop() {
  const wrap = el('div', 'stack');

  const cash = el('p', 'panel-shell__summary',
    `Bargeld: ${money(hud.money.cash)}`);
  wrap.appendChild(cash);

  const list = el('ul', 'itemlist');

  for (const entry of hud.shop) {
    const row = el('li', 'itemlist__row');
    row.appendChild(el('span', 'itemlist__name', entry.name));
    row.appendChild(el('span', 'itemlist__price', money(entry.price)));

    const buy = el('button', 'btn btn--ghost btn--small', 'Kaufen');
    buy.addEventListener('click', () => nui('buy', { code: entry.code, quantity: 1 }));
    row.appendChild(buy);

    // Only show "sell" for things actually carried. The server would refuse
    // anyway; hiding it keeps the panel honest about what is possible.
    const carried = hud.inventory.items.find((i) => i.code === entry.code);
    if (carried) {
      const sell = el('button', 'btn btn--ghost btn--small', `Verkaufen (${carried.quantity})`);
      sell.addEventListener('click', () =>
        nui('sell', { code: entry.code, quantity: carried.quantity }));
      row.appendChild(sell);
    }

    list.appendChild(row);
  }

  wrap.appendChild(list);

  const bank = el('div', 'row-actions');
  const deposit = el('button', 'btn btn--primary btn--small', '100 $ einzahlen');
  deposit.addEventListener('click', () => nui('deposit', { amount: 100 }));
  const withdraw = el('button', 'btn btn--ghost btn--small', '100 $ abheben');
  withdraw.addEventListener('click', () => nui('withdraw', { amount: 100 }));
  bank.append(deposit, withdraw);
  wrap.appendChild(bank);

  return wrap;
}

function panelJobs() {
  const wrap = el('div', 'stack');
  const mine = new Map(hud.jobs.map((j) => [j.code, j]));

  // Every job in the server's roster, not just the ones this character has.
  // The server decides whether a join succeeds; this panel only offers it.
  const roster = (hud.jobCatalogue || []).length
    ? hud.jobCatalogue
    : hud.jobs;

  if (!roster.length) {
    wrap.appendChild(el('p', 'panel-shell__empty', 'Keine Jobs verfügbar.'));
    return wrap;
  }

  const list = el('ul', 'itemlist');

  for (const job of roster) {
    const row = el('li', 'itemlist__row');
    row.appendChild(el('span', 'itemlist__name', job.name));

    const rate = el('span', 'itemlist__price', `${money(job.wagePerHour)}/h`);
    row.appendChild(rate);

    const joined = mine.get(job.code);

    if (!joined) {
      const join = el('button', 'btn btn--primary btn--small', 'Anmelden');
      join.addEventListener('click', () => nui('jobJoin', { code: job.code }));
      row.appendChild(join);
    } else if (joined.onDuty) {
      const end = el('button', 'btn btn--primary btn--small', 'Schicht beenden');
      end.addEventListener('click', () => nui('dutyEnd', { code: job.code }));
      row.appendChild(end);
    } else {
      const start = el('button', 'btn btn--primary btn--small', 'Schicht beginnen');
      start.addEventListener('click', () => nui('dutyStart', { code: job.code }));
      row.appendChild(start);

      const leave = el('button', 'btn btn--ghost btn--small', 'Kündigen');
      leave.addEventListener('click', () => nui('jobLeave', { code: job.code }));
      row.appendChild(leave);
    }

    list.appendChild(row);
  }

  wrap.appendChild(list);
  return wrap;
}

function renderPanel() {
  const shell = $('panel');
  const body = $('panelBody');
  const title = $('panelTitle');
  if (!shell || !body || !title) return;

  if (!hud.panel) {
    shell.classList.add('hidden');
    return;
  }

  const builders = {
    inventory: ['Inventar', panelInventoryProxy],
    shop: ['Shop', panelShop],
    jobs: ['Arbeit', panelJobs],
  };
  const entry = builders[hud.panel];
  if (!entry) {
    shell.classList.add('hidden');
    return;
  }

  title.textContent = entry[0];
  body.innerHTML = '';
  body.appendChild(entry[1]());
  shell.classList.remove('hidden');
}

function renderHud() {
  const root = $('hud');
  if (!root) return;

  root.classList.remove('hidden');

  const cash = $('hudCash');
  const bank = $('hudBank');
  if (cash) cash.textContent = money(hud.money.cash);
  if (bank) bank.textContent = money(hud.money.bank);

  const dutyBox = $('hudDuty');
  const dutyLabel = $('hudDutyLabel');
  const active = hud.jobs.find((j) => j.onDuty);

  if (dutyBox && dutyLabel) {
    if (active) {
      dutyBox.classList.remove('hidden');
      dutyLabel.textContent = active.name;
    } else {
      dutyBox.classList.add('hidden');
    }
  }

  renderPanel();
}

// -------------------------------------------------------------- NUI messages

window.addEventListener('message', (event) => {
  const { action, data } = event.data || {};
  if (!action) return;

  if (action === 'render') {
    // Replace wholesale rather than merge. A field the server omitted (because
    // it no longer exists) must disappear, not linger from the last update.
    Object.assign(hud, {
      money: data.money || hud.money,
      inventory: data.inventory || hud.inventory,
      character: data.character !== undefined ? data.character : hud.character,
      jobs: data.jobs || [],
      jobCatalogue: data.jobCatalogue || [],
      shop: data.shop || [],
      properties: data.properties || [],
      vehicles: data.vehicles || [],
      panel: data.panel || null,
    });
    renderHud();
    return;
  }

  if (action === 'result') {
    showToast(data.ok, data.message);
  }

  if (action === 'phone') {
    renderPhone(data);
  }

  if (action === 'phoneBadge') {
    renderPhoneBadge(Number(data.unread) || 0);
  }

  // Chat. The `data.send` flag on the close is ignored here on purpose: the input
  // sends in `chatCloseInput`, where the text was still readable. Echoing it again
  // from this handler would double every message the player sends.
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
      chatOpenInput();
    } else {
      chatState.open = false;
      const box = $('chatInput');
      if (box) box.classList.add('hidden');
    }
  }
});

// ---------------------------------------------------------------- phone UI
//
// Presentation only. Every value drawn here came from the server in the last
// push; nothing is recomputed, and the send button does not decide whether the
// message is allowed — `phoneSend` hands a typed number to the server, which
// resolves it to a character itself.

const phone = {
  account: null,
  inbox: [],
  unread: 0,
  activeApp: 'messages',
};

function renderPhoneBadge(unread) {
  phone.unread = unread;

  const badge = $('phoneBadgeTop');
  if (!badge) return;

  // Compared as a number, not by truthiness: `0` is truthy in this codebase's
  // Lua heritage and has already caused one bug per language.
  if (unread > 0) {
    badge.textContent = String(unread);
    badge.classList.remove('hidden');
  } else {
    badge.classList.add('hidden');
  }
}

/** "555-0042" stays as is. Anything the server sends as an ISO string is
 *  formatted in the browser's locale rather than assumed to be UTC. */
function formatTime(value) {
  if (!value) return '';
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return String(value);

  return parsed.toLocaleString('de-DE', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function messageRow(message) {
  const row = document.createElement('article');
  row.className = 'phone__message';

  // `read_at` is NULL for an unread message, so the key is simply absent from
  // the table the server sent. `undefined` is the check — `!message.read_at`
  // would also be true for a legitimate epoch timestamp.
  const unread = message.read_at === undefined || message.read_at === null;
  if (unread) row.classList.add('phone__message--unread');

  const meta = document.createElement('div');
  meta.className = 'phone__meta';

  const from = document.createElement('span');
  from.className = 'phone__from';
  // Names come from the server's JOIN on characters; the number is the
  // LEFT JOIN fallback for a sender without a phone account. Never a raw id in
  // the UI — an id on screen reads as a bug, even when it is correct.
  const senderName = [message.sender_first, message.sender_last]
    .filter((part) => typeof part === 'string' && part !== '')
    .join(' ')
    .trim();
  from.textContent = senderName !== ''
    ? senderName
    : (message.sender_number || 'Unbekannt');

  const time = document.createElement('span');
  time.className = 'phone__time';
  time.textContent = formatTime(message.sent_at);

  meta.appendChild(from);
  meta.appendChild(time);

  const body = document.createElement('div');
  body.className = 'phone__body';
  // textContent, never innerHTML: the body is player-authored text, and this is
  // the one place in this UI where that matters most.
  body.textContent = message.body || '';

  const actions = document.createElement('div');
  actions.className = 'phone__actions';

  const reply = document.createElement('button');
  reply.type = 'button';
  reply.className = 'btn btn--ghost btn--small';
  reply.textContent = 'Antworten';
  reply.addEventListener('click', () => {
    const to = $('phoneTo');
    if (to) to.value = message.sender_number || '';
    switchPhoneApp('compose');
    nui('phoneOpenMessage', { id: message.id });
  });

  // Reasons are picked, not typed. `Phone.report` validates against exactly
  // these four and refuses anything else, so the list here is the server's
  // list — a free-text field would mostly produce rejections the player cannot
  // act on.
  const reason = document.createElement('select');
  reason.className = 'phone__reason';
  [
    ['spam', 'Spam'],
    ['harassment', 'Belästigung'],
    ['impersonation', 'Identitätsmissbrauch'],
    ['other', 'Sonstiges'],
  ].forEach(([value, label]) => {
    const option = document.createElement('option');
    option.value = value;
    option.textContent = label;
    reason.appendChild(option);
  });

  const report = document.createElement('button');
  report.type = 'button';
  report.className = 'btn btn--ghost btn--small';
  report.textContent = 'Melden';
  report.addEventListener('click', () => {
    nui('phoneReport', { id: message.id, reason: reason.value });
  });

  actions.appendChild(reply);
  actions.appendChild(reason);
  actions.appendChild(report);

  row.appendChild(meta);
  row.appendChild(body);
  row.appendChild(actions);

  return row;
}

function switchPhoneApp(name) {
  phone.activeApp = name;

  document.querySelectorAll('.phone__tab').forEach((tab) => {
    tab.classList.toggle('is-active', tab.dataset.app === name);
  });

  $('appMessages')?.classList.toggle('is-active', name === 'messages');
  $('appCompose')?.classList.toggle('is-active', name === 'compose');
}

function renderPhone(data) {
  phone.account = data.account || null;
  phone.inbox = Array.isArray(data.inbox) ? data.inbox : [];
  renderPhoneBadge(Number(data.unread) || 0);

  const shell = $('phone');
  if (!shell) return;

  shell.classList.toggle('hidden', data.open !== true);
  if (data.open !== true) return;

  const number = $('phoneNumber');
  if (number) {
    // The server's number, always. The UI has no way to set it.
    number.textContent = phone.account && phone.account.number
      ? phone.account.number
      : '—';
  }

  const list = $('phoneList');
  if (list) {
    list.innerHTML = '';

    if (phone.inbox.length === 0) {
      const empty = document.createElement('p');
      empty.className = 'phone__empty';
      empty.textContent = 'Keine Nachrichten.';
      list.appendChild(empty);
    } else {
      phone.inbox.forEach((message) => list.appendChild(messageRow(message)));
    }
  }
}

function wirePhone() {
  document.querySelectorAll('.phone__tab').forEach((tab) => {
    tab.addEventListener('click', () => switchPhoneApp(tab.dataset.app));
  });

  // The homebar doubles as the close target, which is why there is no X button.
  const homebar = document.querySelector('.phone__homebar');
  if (homebar) homebar.addEventListener('click', () => nui('phoneClose', {}));

  const send = $('phoneSend');
  if (send) {
    send.addEventListener('click', () => {
      const number = ($('phoneTo')?.value || '').trim();
      const body = ($('phoneBody')?.value || '').trim();

      // Empty input is stopped here so the player does not wait for a round
      // trip to be told nothing. This is convenience, NOT a rule — the server
      // performs the same check and is the only thing that enforces it.
      if (number === '' || body === '') {
        showToast(false, 'Nummer und Nachricht werden beide gebraucht.');
        return;
      }

      nui('phoneSend', { number, body });

      const to = $('phoneTo');
      const text = $('phoneBody');
      if (to) to.value = '';
      if (text) text.value = '';

      switchPhoneApp('messages');
    });
  }
}

function wireHud() {
  const close = $('panelClose');
  if (close) close.addEventListener('click', () => nui('closePanel', {}));
}
// ================================================================== chat
//
// The log is passive and never takes focus; only the input does, and only while
// somebody is typing. That split is the reason this is not a panel.
//
// Every line carries its own expiry timer rather than one timer for the whole
// log, because a shared timer makes a five-minute-old line vanish the moment a
// new message arrives, and a chat that forgets is worse than a chat that scrolls.

const CHAT_MAX_LINES = 12;
const CHAT_LINE_MS = 30000;

const chatState = {
  open: false,
};

function chatAddLine(line) {
  const log = $('chatLog');
  if (!log) return;

  const el = document.createElement('div');
  el.className = 'chat-line';

  if (line.system) {
    el.classList.add('chat-line--system');
    el.textContent = line.text || '';
  } else {
    if (line.command) el.classList.add('chat-line--command');

    // Built with textContent, never innerHTML. A chat message is player input;
    // putting it into innerHTML would make every other player a stored-XSS
    // vector against the machine running the server.
    const author = document.createElement('span');
    author.className = 'chat-line__author';
    author.textContent = line.author || '?';
    el.appendChild(author);
    el.appendChild(document.createTextNode(': ' + (line.text || '')));
  }

  log.appendChild(el);

  // Trim from the front, and cancel the timer of the line that goes, or it
  // fires against a detached node for no reason.
  while (log.children.length > CHAT_MAX_LINES) {
    const oldest = log.firstElementChild;
    if (!oldest) break;
    clearTimeout(Number(oldest.dataset.timer || 0));
    log.removeChild(oldest);
  }

  const timer = setTimeout(() => {
    el.classList.add('is-leaving');
    setTimeout(() => el.remove(), 650);
  }, CHAT_LINE_MS);
  el.dataset.timer = String(timer);
}

/** Open the input. The server refuses while the phone holds focus. */
function chatOpenInput() {
  if (chatState.open) return;

  const box = $('chatInput');
  const field = $('chatField');
  if (!box || !field) return;

  chatState.open = true;
  box.classList.remove('hidden');
  field.value = '';
  field.focus();
}

/**
 * Close and tell the server to release focus.
 *
 * The release is a server round trip, not a local state change: focus belongs to
 * Lua, and a client that only hid its own box would leave the cursor captured.
 * That is the single most common FiveM UI bug and the reason this path is not
 * written as a one-liner.
 */
function chatCloseInput(sendText) {
  if (!chatState.open) return;

  const field = $('chatField');
  const text = sendText && field ? field.value.trim() : '';

  chatState.open = false;
  const box = $('chatInput');
  if (box) box.classList.add('hidden');

  nui(sendText ? 'chatSend' : 'chatCancel', { text });

  if (sendText && text !== '') {
    // Echo locally and immediately. Waiting for the server round trip makes the
    // chat feel broken at exactly the moment somebody is trying to talk during
    // something urgent. The server decides what is actually broadcast.
    chatAddLine({ author: 'Du', text });
  }
}

function wireChat() {
  const field = $('chatField');
  if (!field) return;

  field.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      chatCloseInput(true);
    } else if (e.key === 'Escape') {
      e.preventDefault();
      chatCloseInput(false);
    }
  });

  // Losing focus with text in the box would otherwise leave the NUI holding
  // focus over a hidden input. Cancel, do not send: an accidental click must
  // never put a half-typed sentence into the world.
  window.addEventListener('blur', () => {
    if (chatState.open) chatCloseInput(false);
  });
}

wireChat();
