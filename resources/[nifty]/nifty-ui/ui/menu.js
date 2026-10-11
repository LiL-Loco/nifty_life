// Nifty Life 2.0 — the menu framework, page side.
//
// Draws whatever Lua sends and forwards what the player does. It decides NOTHING.
//
// Every string that reaches this file came from a resource and every value that
// leaves it goes back to one, so `textContent` is used everywhere and `innerHTML`
/// nowhere. A menu row can carry a player's chosen name, a shop item or a job
// title, and NUI runs on the machine that runs the server.

const { nui, $ } = Nifty;

// What is on screen. `spec` is the wire form: data all the way down, no functions,
// because the browser cannot call back into Lua and should not be able to.
let spec = null;

// Index of the highlighted row, and the index of the highlighted LIST row when the
// selected row is a list. A list is one row in the menu but many rows on screen, so
// these are separate cursors — otherwise arrowing through a list of forty shoes
// moves the menu's highlight instead of the shoes.
let rowIndex = 0;
let listIndex = 0;

let dragging = null;

// True while a text field has the keyboard. The menu's own keydown handler bails out
// while this is set, otherwise typing a name also moves the highlighted row.
let editing = false;

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function labelOf(item) {
  const el = document.createElement('div');
  el.className = 'row__label';

  const text = document.createElement('span');
  text.textContent = item.label || '';
  el.appendChild(text);

  if (item.description) {
    const desc = document.createElement('small');
    desc.className = 'row__desc';
    desc.textContent = item.description;
    el.appendChild(desc);
  }

  return el;
}

/** A checkbox box. The tick is a CSS pseudo-element, never a glyph from a string. */
function checkboxEl(item) {
  const el = document.createElement('div');
  el.className = 'check' + (item.checked ? ' is-on' : '');
  return el;
}

function sliderEl(item) {
  const wrap = document.createElement('div');
  wrap.className = 'slider';

  const track = document.createElement('div');
  track.className = 'slider__track';

  const fill = document.createElement('div');
  fill.className = 'slider__fill';

  const thumb = document.createElement('div');
  thumb.className = 'slider__thumb';

  const value = document.createElement('span');
  value.className = 'slider__value';

  const paint = () => {
    const span = item.max - item.min;
    const ratio = span > 0 ? (item.value - item.min) / span : 0;
    fill.style.width = (ratio * 100) + '%';
    thumb.style.left = (ratio * 100) + '%';
    value.textContent = String(item.value);
  };

  // Stored on the element so the drag handler and the repaint agree on one number
  // rather than each recomputing from the DOM.
  thumb.__paint = paint;
  thumb.__item = item;

  track.appendChild(fill);
  track.appendChild(thumb);
  wrap.appendChild(track);
  wrap.appendChild(value);

  paint();
  return wrap;
}

function selectEl(item) {
  const value = document.createElement('span');
  value.className = 'row__value';
  value.textContent = (item.items && item.items[item.index - 1]) || '—';
  return value;
}

/**
 * A text field, rendered inside its row.
 *
 * It takes the keyboard when focused, which makes it the ONE row type that steals
 * arrow keys from the menu itself. `editing` below is what stops the menu's global
 * keydown handler from also moving the highlight while somebody types a name —
 * without it, typing "J" jumps the selection and then inserts "J".
 */
function inputEl(item) {
  const field = document.createElement('input');
  field.type = 'text';
  field.className = 'row__field';
  field.value = item.value || '';
  field.placeholder = item.placeholder || '';
  field.maxLength = item.maxLength || 64;
  field.autocomplete = 'off';
  field.spellcheck = false;

  field.addEventListener('input', () => {
    item.value = field.value;
  });

  field.addEventListener('change', () => {
    item.value = field.value;
    if (spec) nui('menuChange', { menuId: spec.id, index: rowIndex, text: item.value });
  });

  field.addEventListener('focus', () => { editing = true; });
  field.addEventListener('blur', () => { editing = false; });

  field.addEventListener('keydown', (e) => {
    e.stopPropagation();
    if (e.key === 'Enter') field.blur();
    if (e.key === 'Escape') field.blur();
  });

  return field;
}

/**
 * Turn a client pixel position into a value inside the row's range.
 *
 * The track's own geometry is used rather than a hardcoded width, because the
 * panel is width-constrained by the dock mode and a fixed width would put the
 * thumb somewhere other than under the cursor in one of the two layouts.
 */
function valueFromPointer(clientX) {
  const item = dragging.item;
  const rect = dragging.track.getBoundingClientRect();

  const ratio = Math.min(1, Math.max(0, (clientX - rect.left) / rect.width));

  const raw = item.min + ratio * (item.max - item.min);
  const stepped = item.min + Math.floor((raw - item.min) / item.step + 0.5) * item.step;

  return Math.min(item.max, Math.max(item.min, stepped));
}

function listEl(item) {
  const wrap = document.createElement('div');
  wrap.className = 'menu__list';

  const rows = item.rows || [];
  if (rows.length === 0) {
    const empty = document.createElement('p');
    empty.className = 'menu__empty';
    empty.textContent = 'Keine Einträge.';
    wrap.appendChild(empty);
    return wrap;
  }

  rows.forEach((row, i) => {
    const el = document.createElement('div');
    el.className = 'listrow' + (i === listIndex ? ' is-active' : '');

    const name = document.createElement('span');
    name.className = 'listrow__name';
    name.textContent = row.label || '';

    el.appendChild(name);

    if (row.right) {
      const right = document.createElement('span');
      right.className = 'listrow__right';
      right.textContent = row.right;
      el.appendChild(right);
    }

    el.addEventListener('click', (e) => {
      e.stopPropagation();
      if (!spec) return;
      nui('menuSelect', { menuId: spec.id, index: rowIndex, row: i + 1 });
    });

    wrap.appendChild(el);
  });

  return wrap;
}

function buildRow(item, index) {
  const row = document.createElement('div');
  row.className = 'row' + (index === rowIndex ? ' is-active' : '');
  if (item.disabled) row.classList.add('is-disabled');

  if (item.kind === 'separator') {
    row.className = 'row row--separator';
    row.textContent = item.label || '';
    return row;
  }

  row.appendChild(labelOf(item));

  if (item.kind === 'checkbox') {
    row.appendChild(checkboxEl(item));
  } else if (item.kind === 'slider') {
    row.appendChild(sliderEl(item));
  } else if (item.kind === 'select') {
    row.appendChild(selectEl(item));
  } else if (item.kind === 'input') {
    row.appendChild(inputEl(item));
  } else if (item.kind === 'submenu') {
    const chev = document.createElement('span');
    chev.className = 'row__chevron';
    chev.textContent = '›';
    row.appendChild(chev);
  }

  row.addEventListener('click', () => {
    if (item.disabled) return;
    rowIndex = index;
    activate(item, index);
  });

  return row;
}

function activate(item, index) {
  if (!spec) return;

  if (item.kind === 'submenu') {
    nui('menuSubmenu', { menuId: spec.id, index });
    return;
  }

  if (item.kind === 'checkbox') {
    item.checked = !item.checked;
    nui('menuChange', { menuId: spec.id, index, checked: item.checked });
    render();
    return;
  }

  if (item.kind === 'slider') {
    return;   // driven by the handle, not the row
  }

  if (item.kind === 'select') {
    item.index = item.index >= (item.items || []).length ? 1 : item.index + 1;
    // `index` is the ROW index. The chosen position is `value`, on both sides —
    // sending it as `index` would arrive as the row number and select the wrong
    // entry, which on a nine-item list looks like the control simply not working.
    nui('menuChange', { menuId: spec.id, index: rowIndex, value: item.index });
    render();
    return;
  }

  // button and list both confirm here.
  nui('menuSelect', {
    menuId: spec.id,
    index,
    row: item.kind === 'list' ? listIndex + 1 : null,
  });

  // A button that does not change the menu repaints it, so a row that changes its
  // own label or disabled state is visible without the caller asking for it.
  render();
}

function render() {
  const root = $('menuRoot');
  const body = $('menuBody');
  if (!root || !body) return;

  if (!spec) {
    root.classList.add('hidden');
    return;
  }

  root.classList.remove('hidden');
  root.dataset.dock = spec.dock || 'center';

  $('menuTitle').textContent = spec.title || '';

  const subtitle = $('menuSubtitle');
  subtitle.textContent = spec.subtitle || '';
  subtitle.classList.toggle('hidden', !spec.subtitle);

  body.innerHTML = '';

  (spec.items || []).forEach((item, i) => {
    body.appendChild(buildRow(item, i));

    // A list is drawn UNDER its own row, not inside it: forty shoes inside one row
    // makes the row taller than the panel and pushes every other menu out of view.
    if (item.kind === 'list') body.appendChild(listEl(item));
  });

  if ((spec.items || []).length === 0) {
    const empty = document.createElement('p');
    empty.className = 'menu__empty';
    empty.textContent = 'Leer.';
    body.appendChild(empty);
  }
}

// ---------------------------------------------------------------------------
// Keyboard
//
// Menus are driven from the keyboard, not the mouse. A menu is opened from a game
// key, so the player's hands are on the keyboard, and a slider that can only be
// dragged is a control that cannot be used by the person who opened the menu.
// ---------------------------------------------------------------------------

function currentRow() {
  if (!spec) return null;
  return spec.items[rowIndex] || null;
}

function move(delta) {
  if (!spec || !spec.items.length) return;

  let next = rowIndex;
  for (let i = 0; i < spec.items.length; i++) {
    next = (next + delta + spec.items.length) % spec.items.length;
    if (spec.items[next].kind !== 'separator') break;
  }

  rowIndex = next;
  listIndex = 0;
  render();
}

function nudgeSlider(delta) {
  const item = currentRow();
  if (!item || item.kind !== 'slider') return;

  let value = item.value + delta * item.step;
  value = Math.min(item.max, Math.max(item.min, value));

  if (value === item.value) return;

  item.value = value;
  nui('menuChange', { menuId: spec.id, index: rowIndex, value });
  render();
}

window.addEventListener('keydown', (e) => {
  if (!spec) return;

  const item = currentRow();

  if (e.key === 'Escape' || e.key === 'Backspace') {
    e.preventDefault();
    nui('menuBack', {});
    return;
  }

  if (e.key === 'ArrowDown') { e.preventDefault(); move(1); return; }
  if (e.key === 'ArrowUp')   { e.preventDefault(); move(-1); return; }

  if (item && item.kind === 'list' && (e.key === 'ArrowRight' || e.key === 'ArrowLeft')) {
    e.preventDefault();
    const rows = item.rows || [];
    if (!rows.length) return;

    listIndex = (listIndex + (e.key === 'ArrowRight' ? 1 : -1) + rows.length) % rows.length;
    render();
    return;
  }

  // Left/right on a slider nudges it. On anything else they are not swallowed, so
  // a list still gets them and no other binding is stolen.
  if (e.key === 'ArrowRight') { e.preventDefault(); nudgeSlider(1); return; }
  if (e.key === 'ArrowLeft')  { e.preventDefault(); nudgeSlider(-1); return; }

  if (e.key === 'Enter') {
    e.preventDefault();
    if (item && item.kind === 'input') {
      const field = document.querySelector('.row.is-active .row__field');
      if (field) field.focus();
      return;
    }
    if (item) activate(item, rowIndex);
    return;
  }

  if (e.key === ' ' && item && item.kind === 'checkbox') {
    e.preventDefault();
    activate(item, rowIndex);
  }
});

// ---------------------------------------------------------------------------
// Slider dragging
// ---------------------------------------------------------------------------

document.addEventListener('mousedown', (e) => {
  const thumb = e.target.classList && e.target.classList.contains('slider__thumb') ? e.target : null;
  if (!thumb || !spec) return;

  dragging = { item: thumb.__item, track: thumb.parentNode, paint: thumb.__paint };
  e.preventDefault();
});

document.addEventListener('mousemove', (e) => {
  if (!dragging) return;

  const value = valueFromPointer(e.clientX);
  if (value === dragging.item.value) return;

  dragging.item.value = value;
  dragging.paint();
});

document.addEventListener('mouseup', () => {
  if (!dragging) return;

  const item = dragging.item;
  dragging = null;

  nui('menuChange', { menuId: spec.id, index: rowIndex, value: item.value });
});

document.addEventListener('mouseleave', () => { dragging = null; });

// ---------------------------------------------------------------------------
// Messages from Lua
// ---------------------------------------------------------------------------

window.addEventListener('message', (event) => {
  const { action, data } = event.data || {};
  if (!action) return;

  if (action === 'menuOpen') {
    spec = data;
    rowIndex = 0;
    listIndex = 0;

    // Open on the first row that can be activated, not blindly on row 0. A menu
    // whose first entry is a separator would otherwise open with nothing lit.
    while (spec.items[rowIndex] && spec.items[rowIndex].kind === 'separator') rowIndex++;

    render();
    return;
  }

  if (action === 'menuClose') {
    spec = null;
    dragging = null;
    render();
    return;
  }
});

$('menuClose')?.addEventListener('click', () => {
  if (!spec) return;
  nui('menuClosed', { menuId: spec.id });
});

// Losing focus with a menu up means the browser lost the keyboard, and the game
// got it back. Say so, or the menu stays on screen over a player who cannot use it.
window.addEventListener('blur', () => {
  if (!spec) return;
  nui('menuClosed', { menuId: spec.id });
});

render();