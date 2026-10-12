// Nifty Wardrobe — NUI client.
// Single panel that swaps between the slot list, the per-slot owned
// pieces, the outfit list, and the outfit-save dialog. No panel-stack;
// the wardrobe has at most three "screens" and we swap the inner HTML
// rather than animate a stack.
//
// State is held by Lua (nifty-clothing/client/cl_wardrobe.lua).
// NUI receives pushes via 'open' / 'refresh' / 'close' and posts back
// via fetch NUI.

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
    screen: 'root',  // 'root' | 'slot' | 'outfits' | 'outfit-actions' | 'rename' | 'save'
    character: { firstName: '', lastName: '' },
    slots: [],
    owned: {},
    outfits: [],
    componentLabels: {},
    propLabels: {},
    activeSlot: null,
    activeOutfit: null,
    saveName: '',
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
    b.addEventListener('click', onClick);
    return b;
  };
  const separator = (label) => el('div', 'wc-separator', label);
  const input = (placeholder, value, onChange) => {
    const i = el('input', 'wc-input');
    i.type = 'text';
    i.placeholder = placeholder;
    i.value = value || '';
    i.addEventListener('input', (e) => onChange(e.target.value));
    return i;
  };

  // ---------------------------------------------------------------- screens
  const renderRoot = () => {
    const root = el('div', '');
    root.appendChild(separator('Kleidung'));
    for (const s of state.slots) {
      const label = state.componentLabels[s] || ('Slot ' + s);
      root.appendChild(button(label, 'Slot ' + s, () => {
        state.activeSlot = { kind: 'components', id: s };
        state.screen = 'slot';
        fetchNui('getOwnedForSlot', { kind: 'components', id: s });
        renderPanel();
      }));
    }
    if (state.slots.props && state.slots.props.length > 0) {
      root.appendChild(separator('Accessoires'));
      for (const s of state.slots.props) {
        const label = state.propLabels[s] || ('Prop ' + s);
        root.appendChild(button(label, 'Prop ' + s, () => {
          state.activeSlot = { kind: 'props', id: s };
          state.screen = 'slot';
          fetchNui('getOwnedForSlot', { kind: 'props', id: s });
          renderPanel();
        }));
      }
    }
    root.appendChild(separator('Outfits'));
    root.appendChild(button('Outfits ansehen', null, () => {
      state.screen = 'outfits';
      fetchNui('getOutfits');
      renderPanel();
    }));
    root.appendChild(button('Outfit speichern', 'Aktuelles Outfit unter Name ablegen.', () => {
      state.screen = 'save';
      state.saveName = '';
      renderPanel();
    }));
    return root;
  };

  const renderSlot = () => {
    const root = el('div', '');
    if (!state.activeSlot) { state.screen = 'root'; return renderRoot(); }
    const { kind, id } = state.activeSlot;
    const label = (kind === 'props'
      ? state.propLabels[id]
      : state.componentLabels[id]) || (kind + ' ' + id);
    root.appendChild(button('< Zurueck', null, () => {
      state.screen = 'root';
      state.activeSlot = null;
      renderPanel();
    }, { chevron: false }));
    root.appendChild(separator(label));
    root.appendChild(button('Ablegen', 'Slot leeren.', () => {
      fetchNui('unequip', { kind, id });
    }));
    const pieces = state.owned[kind] && state.owned[kind][id] || [];
    if (pieces.length === 0) {
      root.appendChild(el('div', 'wc-separator', 'Keine Stuecke.'));
    } else {
      for (const p of pieces) {
        root.appendChild(button(p.name || ('Stueck ' + p.id), p.collection, () => {
          fetchNui('equip', { kind, id, pieceId: p.id });
        }));
      }
    }
    return root;
  };

  const renderOutfits = () => {
    const root = el('div', '');
    root.appendChild(button('< Zurueck', null, () => {
      state.screen = 'root';
      renderPanel();
    }, { chevron: false }));
    root.appendChild(separator('Outfits'));
    if (state.outfits.length === 0) {
      root.appendChild(el('div', 'wc-separator', 'Keine Outfits gespeichert.'));
    } else {
      for (const o of state.outfits) {
        const row = el('div', '');
        const main = button(o.name, 'Klicken fuer Aktionen', () => {
          state.activeOutfit = o;
          state.screen = 'outfit-actions';
          renderPanel();
        }, { chevron: true });
        row.appendChild(main);
        // Direct-apply on long-name double-click (gesture omitted)
        // is too subtle; use the action screen for everything.
        root.appendChild(row);
      }
    }
    return root;
  };

  // Per-outfit action screen: Anziehen, Umbenennen, Loeschen.
  const renderOutfitActions = () => {
    const root = el('div', '');
    const o = state.activeOutfit;
    if (!o) { state.screen = 'outfits'; return renderOutfits(); }
    root.appendChild(button('< Zurueck', null, () => {
      state.activeOutfit = null;
      state.screen = 'outfits';
      renderPanel();
    }, { chevron: false }));
    root.appendChild(separator(o.name));
    root.appendChild(button('Anziehen', 'Outfit jetzt tragen.', () => {
      fetchNui('applyOutfit', { id: o.id });
    }));
    root.appendChild(button('Umbenennen', 'Namen aendern.', () => {
      state.screen = 'rename';
      state.saveName = o.name;
      renderPanel();
    }));
    root.appendChild(button('Loeschen', 'Outfit entgueltig entfernen.', () => {
      fetchNui('deleteOutfit', { id: o.id });
      state.activeOutfit = null;
      state.screen = 'outfits';
    }, { danger: true }));
    return root;
  };

  // Rename dialog: a single text input + Save button.
  const renderRename = () => {
    const root = el('div', '');
    root.appendChild(button('< Abbrechen', null, () => {
      state.screen = 'outfit-actions';
      renderPanel();
    }, { chevron: false }));
    root.appendChild(separator('Outfit umbenennen'));
    const nameInput = input('Neuer Name', state.saveName, (v) => {
      state.saveName = v;
    });
    nameInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        const o = state.activeOutfit;
        if (o) fetchNui('renameOutfit', { id: o.id, name: state.saveName });
        state.activeOutfit = null;
        state.screen = 'outfits';
      }
    });
    root.appendChild(nameInput);
    root.appendChild(button('Speichern', null, () => {
      const o = state.activeOutfit;
      if (o) fetchNui('renameOutfit', { id: o.id, name: state.saveName });
      state.activeOutfit = null;
      state.screen = 'outfits';
    }, { primary: true }));
    return root;
  };

  const renderSave = () => {
    const root = el('div', '');
    root.appendChild(button('< Zurueck', null, () => {
      state.screen = 'root';
      renderPanel();
    }, { chevron: false }));
    root.appendChild(separator('Outfit speichern'));
    const nameInput = input('Name des Outfits', state.saveName, (v) => {
      state.saveName = v;
    });
    nameInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') fetchNui('saveOutfit', { name: state.saveName });
    });
    root.appendChild(nameInput);
    root.appendChild(button('Speichern', null, () => {
      fetchNui('saveOutfit', { name: state.saveName });
    }, { primary: true }));
    return root;
  };

  // ---------------------------------------------------------------- render
  const renderPanel = () => {
    const panel = document.getElementById('panel');
    if (!panel) return;
    panel.innerHTML = '';
    let dom;
    switch (state.screen) {
      case 'slot':             dom = renderSlot(); break;
      case 'outfits':          dom = renderOutfits(); break;
      case 'outfit-actions':  dom = renderOutfitActions(); break;
      case 'rename':           dom = renderRename(); break;
      case 'save':             dom = renderSave(); break;
      default:                 dom = renderRoot(); break;
    }
    if (dom) panel.appendChild(dom);
  };

  // ---------------------------------------------------------------- message
  window.addEventListener('message', (e) => {
    const { action, data } = e.data || {};
    if (!action) return;
    // The wardrobe is one of two UIs on the same page; only react
    // when the open message says so. The store listens to the same
    // stream but filters on mode === 'store' instead.
    if (action === 'open' && data && data.mode && data.mode !== 'wardrobe') return;
    if (action === 'storeList' || action === 'purchaseResult') return;
    switch (action) {
      case 'open':
        state.open = true;
        if (data.character) state.character = data.character;
        if (data.slots) state.slots = data.slots;
        if (data.outfits) state.outfits = data.outfits;
        if (data.componentLabels) state.componentLabels = data.componentLabels;
        if (data.propLabels) state.propLabels = data.propLabels;
        document.getElementById('root').classList.remove('hidden');
        const title = document.getElementById('title');
        if (title) title.textContent = 'WARDROBE';
        state.screen = 'root';
        renderPanel();
        break;
      case 'refresh':
        if (data.owned) state.owned = data.owned;
        if (data.outfits) state.outfits = data.outfits;
        renderPanel();
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
      else { state.screen = 'root'; renderPanel(); }
    }
  });
})();
