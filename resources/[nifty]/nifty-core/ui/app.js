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
  jobs: [],
  jobCatalogue: [],
  shop: [],
  properties: [],
  vehicles: [],
  panel: null,
};

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

// ------------------------------------------------------------------- panels

function panelInventory() {
  const wrap = el('div', 'stack');

  const summary = el('p', 'panel-shell__summary');
  summary.textContent =
    `${hud.inventory.usedSlots}/${hud.inventory.totalSlots} Plätze · ` +
    `${money(hud.inventory.usedWeight)} / ${money(hud.inventory.maxWeight)}`;
  wrap.appendChild(summary);

  if (!hud.inventory.items.length) {
    wrap.appendChild(el('p', 'panel-shell__empty', 'Du trägst nichts.'));
    return wrap;
  }

  const list = el('ul', 'itemlist');

  for (const item of hud.inventory.items) {
    const row = el('li', 'itemlist__row');
    row.appendChild(el('span', 'itemlist__name', `${item.name}`));

    const weight = el('span', 'itemlist__weight',
      `${item.quantity} × ${money(item.unitWeight)}`);
    row.appendChild(weight);

    const use = el('button', 'btn btn--ghost btn--small', 'Benutzen');
    use.addEventListener('click', () => nui('useItem', {
      code: item.code, quantity: 1,
    }));
    row.appendChild(use);

    list.appendChild(row);
  }

  wrap.appendChild(list);
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
    inventory: ['Inventar', panelInventory],
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
});

function wireHud() {
  const close = $('panelClose');
  if (close) close.addEventListener('click', () => nui('closePanel', {}));
}