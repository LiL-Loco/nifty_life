// Nifty Spawn Picker — NUI client.
//
// Renders a list of spawn locations. Tapping one fires the
// `pickSpawn` callback with the location's key; the Lua side then
// flies the camera and updates `currentPick` server-side. The
// player confirms with "Bestaetigen" or cancels with "Abbrechen".

(() => {
  'use strict';

  const el = (tag, cls, text) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  };
  const fetchNui = async (name, body) => {
    try {
      const res = await fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(body || {}),
      });
      if (!res.ok) return null;
      return await res.json();
    } catch (_) { return null; }
  };

  // ---------------------------------------------------------------- state
  const state = {
    open: false,
    locations: [],
    currentKey: null,
  };

  // ---------------------------------------------------------------- widgets
  const button = (label, onClick, opts = {}) => {
    const b = el('button', 'sp-btn');
    const lbl = el('span', 'sp-btn__label', label);
    b.appendChild(lbl);
    if (opts.chevron !== false) b.appendChild(el('span', 'sp-btn__chevron', '›'));
    if (opts.primary) b.classList.add('sp-btn--primary');
    if (opts.danger) b.classList.add('sp-btn--danger');
    if (opts.active) b.classList.add('sp-btn--active');
    b.addEventListener('click', onClick);
    return b;
  };
  const separator = (label) => el('div', 'sp-separator', label);

  // ---------------------------------------------------------------- render
  const renderPanel = () => {
    const panel = document.getElementById('panel');
    if (!panel) return;
    panel.innerHTML = '';
    const root = el('div', '');
    root.appendChild(separator('Orte'));
    for (const loc of state.locations) {
      const isCurrent = loc.key === state.currentKey;
      root.appendChild(button(
        isCurrent ? ('› ' + loc.label) : loc.label,
        () => fetchNui('pickSpawn', { key: loc.key }),
        { chevron: false, active: isCurrent }
      ));
    }
    root.appendChild(separator('Aktionen'));
    root.appendChild(button('Bestaetigen', () => {
      fetchNui('confirmSpawn', { confirmed: true });
    }, { primary: true }));
    root.appendChild(button('Abbrechen', () => {
      fetchNui('confirmSpawn', { confirmed: false });
    }, { danger: true }));
    panel.appendChild(root);
  };

  // ---------------------------------------------------------------- message
  window.addEventListener('message', (e) => {
    const { action, data } = e.data || {};
    if (!action) return;
    switch (action) {
      case 'open':
        state.open = true;
        if (data && data.locations) state.locations = data.locations;
        if (data && data.currentKey) state.currentKey = data.currentKey;
        document.getElementById('root').classList.remove('hidden');
        renderPanel();
        break;
      case 'update':
        if (data && data.currentKey !== undefined) state.currentKey = data.currentKey;
        renderPanel();
        break;
      case 'close':
        state.open = false;
        document.getElementById('root').classList.add('hidden');
        document.getElementById('panel').innerHTML = '';
        break;
    }
  });

  // ---------------------------------------------------------------- keyboard
  document.addEventListener('keydown', (e) => {
    if (!state.open) return;
    if (e.key === 'Escape') {
      fetchNui('confirmSpawn', { confirmed: false });
    }
  });
})();
