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
  $('creator').classList.add('hidden');
});