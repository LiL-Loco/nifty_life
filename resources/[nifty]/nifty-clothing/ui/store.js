// Nifty Store — NUI client.
//
// Single-page surface that swaps between the slot picker and the
// per-slot item list. The Lua side is a thin bridge (cl_nui.lua);
// the actual item list and prices come from the server via
// 'nifty:client:storeListForSlot'.

(() => {
  'use strict';

  const el = (tag, cls, text) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  };
  const money = (n) => Number(n || 0).toLocaleString('de-DE', {
    minimumFractionDigits: 0, maximumFractionDigits: 2,
  });
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
  const toast = (message, isError = false, ms = 3200) => {
    const t = document.getElementById('toast');
    if (!t) return;
    t.textContent = message || '';
    t.classList.remove('hidden', 'toast--error');
    if (isError) t.classList.add('toast--error');
    clearTimeout(+t.dataset.timer);
    t.dataset.timer = String(setTimeout(() => t.classList.add('hidden'), ms));
  };

  // ---------------------------------------------------------------- state
  const state = {
    open: false,
    screen: 'root',  // 'root' | 'slot'
    componentSlots: [1, 2, 3, 4, 5, 7, 8, 11],
    propSlots:      [0, 1, 2, 6, 7],
    componentLabels: {
      1: 'Masken', 2: 'Haare', 3: 'Oberkoerper', 4: 'Hosen',
      5: 'Schuhe',  7: 'Accessoires', 8: 'Unterhemden', 11: 'Oberteile',
    },
    propLabels: {
      0: 'Kopfbedeckung', 1: 'Brille', 2: 'Ohrring',
      6: 'Schmuck',       7: 'Uhr',
    },
    activeSlot: null,   // { kind, id }
    items: {},          // { [kindId]: [{ drawable, texture, name, price }] }
    itemsLoading: false,
  };

  // ---------------------------------------------------------------- widgets
  const button = (label, desc, onClick, opts = {}) => {
    const b = el('button', 'wc-btn');
    const left = el('div');
    left.appendChild(el('div', 'wc-btn__label', label));
    if (desc) left.appendChild(el('div', 'wc-btn__desc', desc));
    b.appendChild(left);
    if (opts.chevron !== false) b.appendChild(el('span', 'wc-btn__chevron', '›'));
    if (opts.danger) b.classList.add('wc-btn--danger');
    if (opts.primary) b.classList.add('wc-btn--primary');
    if (opts.disabled) b.disabled = true;
    b.addEventListener('click', onClick);
    return b;
  };
  const separator = (label) => el('div', 'wc-separator', label);

  // ---------------------------------------------------------------- screens
  const renderRoot = () => {
    const root = el('div', '');
    root.appendChild(separator('Komponenten'));
    for (const s of state.componentSlots) {
      const label = state.componentLabels[s] || ('Slot ' + s);
      root.appendChild(button(label, 'Klicken zum Kaufen.', () => {
        state.activeSlot = { kind: 'component', id: s };
        state.screen = 'slot';
        state.itemsLoading = true;
        state.items[slotKey('component', s)] = null;
        renderPanel();
        fetchNui('getStoreListForSlot', { kind: 'component', id: s });
      }));
    }
    if (state.propSlots.length > 0) {
      root.appendChild(separator('Accessoires'));
      for (const s of state.propSlots) {
        const label = state.propLabels[s] || ('Prop ' + s);
        root.appendChild(button(label, 'Klicken zum Kaufen.', () => {
          state.activeSlot = { kind: 'prop', id: s };
          state.screen = 'slot';
          state.itemsLoading = true;
          state.items[slotKey('prop', s)] = null;
          renderPanel();
          fetchNui('getStoreListForSlot', { kind: 'prop', id: s });
        }));
      }
    }
    return root;
  };

  const slotKey = (kind, id) => kind + ':' + id;
  const labelForSlot = (kind, id) => {
    if (kind === 'component') return state.componentLabels[id] || ('Slot ' + id);
    if (kind === 'prop')      return state.propLabels[id]      || ('Prop ' + id);
    return 'Slot ' + id;
  };

  const renderSlot = () => {
    const root = el('div', '');
    if (!state.activeSlot) { state.screen = 'root'; return renderRoot(); }
    const { kind, id } = state.activeSlot;
    const label = labelForSlot(kind, id);
    const cacheKey = slotKey(kind, id);
    const items = state.items[cacheKey];

    root.appendChild(button('< Zurueck', null, () => {
      state.activeSlot = null;
      state.screen = 'root';
      renderPanel();
    }, { chevron: false }));
    root.appendChild(separator(label));

    if (state.itemsLoading && !items) {
      root.appendChild(separator('Lade ...'));
    } else if (items && items.length === 0) {
      root.appendChild(el('div', 'wc-separator', 'Aktuell nichts im Angebot.'));
    } else if (items) {
      for (const item of items) {
        const itemLabel = (item.name || ('Stueck #' + item.drawable))
          + '   -$' + money(item.price || 0);
        const copy = item;
        root.appendChild(button(itemLabel, 'Kauf und ziehe dieses Stueck direkt an.', () => {
          fetchNui('purchaseItem', {
            kind:      kind,
            slot_id:   id,
            drawable:  copy.drawable,
            texture:   copy.texture,
          });
        }));
      }
    }
    return root;
  };

  // ---------------------------------------------------------------- render
  const renderPanel = () => {
    const panel = document.getElementById('panel');
    if (!panel) return;
    panel.innerHTML = '';
    const dom = state.screen === 'slot' ? renderSlot() : renderRoot();
    if (dom) panel.appendChild(dom);
  };

  // ---------------------------------------------------------------- message
  window.addEventListener('message', (e) => {
    const { action, data } = e.data || {};
    if (!action) return;
    // The store only reacts when the open message says so. The
    // wardrobe listens to the same stream but filters on
    // mode === 'wardrobe' instead.
    if (action === 'open' && data && data.mode && data.mode !== 'store') return;
    if (action === 'refresh' || action === 'outfitList') return;
    switch (action) {
      case 'open':
        state.open = true;
        document.getElementById('root').classList.remove('hidden');
        const title = document.getElementById('title');
        if (title) title.textContent = 'KLAMOTTENLADEN';
        const sub = document.getElementById('subtitle');
        if (sub) sub.textContent = 'Kleidung, Accessoires und Preise.';
        state.screen = 'root';
        state.items = {};
        state.itemsLoading = false;
        renderPanel();
        break;
      case 'storeList':
        if (data && data.kind && (data.id !== undefined)) {
          state.items[slotKey(data.kind, data.id)] = data.items || [];
          state.itemsLoading = false;
          renderPanel();
        }
        break;
      case 'purchaseResult':
        if (data && data.ok) {
          toast('Gekauft fuer $' + money(data.price || 0));
          setTimeout(() => fetchNui('closePanel'), 800);
        } else {
          toast('Kauf fehlgeschlagen: ' + (data && data.reason ? data.reason : 'unbekannt'), true);
        }
        break;
      case 'close':
        state.open = false;
        document.getElementById('root').classList.add('hidden');
        document.getElementById('panel').innerHTML = '';
        break;
    }
  });

  // ---------------------------------------------------------------- close button
  const closeBtn = document.getElementById('closeBtn');
  if (closeBtn) closeBtn.addEventListener('click', () => fetchNui('closePanel'));

  // ---------------------------------------------------------------- keyboard
  document.addEventListener('keydown', (e) => {
    if (!state.open) return;
    const tag = (e.target && e.target.tagName) || '';
    if (e.key === 'Escape') {
      if (tag === 'INPUT') { e.target.blur(); return; }
      if (state.screen === 'root') fetchNui('closePanel');
      else { state.screen = 'root'; state.activeSlot = null; renderPanel(); }
    }
  });
})();
