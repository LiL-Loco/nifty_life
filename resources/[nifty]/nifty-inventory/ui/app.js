// Nifty Life 2.0 — inventory panel (nifty-inventory/ui/).
//
// Lives in its own CEF (nifty-inventory's ui_page). cl_inventory.lua
// sends `{action: 'open' | 'refresh' | 'close'}` updates; this file
// renders the four-section grid (BACKPACK / OUTFIT / QUICK ACCESS /
// ENVIRONMENT) and wires the right-click context menu on BACKPACK tiles.

(function () {
  'use strict';

  // -------------------------------------------------------------- helpers
  const $ = (id) => document.getElementById(id);
  const el = (tag, cls, text) => {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined) node.textContent = text;
    return node;
  };
  const money = (n) => {
    const v = Number(n) || 0;
    return v.toLocaleString('de-DE', {
      minimumFractionDigits: v % 1 === 0 ? 0 : 2,
      maximumFractionDigits: 2,
    });
  };

  const COMPONENT_NAMES = {
    1: 'Maske', 2: 'Haar', 3: 'Oberkörper', 4: 'Hose', 5: 'Schuhe',
    6: 'Socken', 7: 'Jacke', 8: 'Unterhemd', 9: 'Krawatte',
    10: 'Gürtel', 11: 'Oberteil',
  };
  const PROP_NAMES = {
    0: 'Mütze', 1: 'Brille', 2: 'Ohrring', 3: 'Uhr', 4: 'Armband', 5: 'Ring',
  };

  // Per-character inventory UI settings. Persisted in localStorage
  // under `nifty.inv.settings.v1`. Loaded once on load; toggles flip
  // immediately.
  const invSettings = (() => {
    try {
      const raw = localStorage.getItem('nifty.inv.settings.v1');
      if (raw) return JSON.parse(raw);
    } catch (_) {}
    return {
      showBackpack: true, showOutfit: true,
      showQuickAccess: true, showEnvironment: true,
    };
  })();
  function saveInvSettings() {
    try { localStorage.setItem('nifty.inv.settings.v1', JSON.stringify(invSettings)); }
    catch (_) {}
  }

  // -------------------------------------------------------------- state
  let hud = { inventory: { items: [], usedSlots: 0 }, character: null };

  function applyVisibility(sections) {
    sections.backpack.classList.toggle('hidden',   !invSettings.showBackpack);
    sections.outfit.classList.toggle('hidden',     !invSettings.showOutfit);
    sections.quick.classList.toggle('hidden',      !invSettings.showQuickAccess);
    sections.environment.classList.toggle('hidden', !invSettings.showEnvironment);
  }

  // -------------------------------------------------------------- worn items
  function wornItemsFromAppearance(appearance) {
    if (!appearance || typeof appearance !== 'object') return [];
    const out = [];
    const labelFor = (kind, slotId, drawable) => {
      if (kind === 'component') {
        const m = COMPONENT_NAMES[slotId];
        return `${m || ('Slot ' + slotId)} #${drawable}`;
      }
      const m = PROP_NAMES[slotId];
      return `${m || ('Prop ' + slotId)} #${drawable}`;
    };
    for (const k of Object.keys(appearance.components || {})) {
      const sid = Number(k);
      const s = appearance.components[k];
      if (!s || sid === undefined) continue;
      out.push({
        code: 'clothing_component_' + sid,
        name: labelFor('component', sid, s.drawable),
        slot_kind: 'component', slot_id: sid,
        quantity: 1, unitWeight: 0,
      });
    }
    for (const k of Object.keys(appearance.props || {})) {
      const sid = Number(k);
      const s = appearance.props[k];
      if (!s) continue;
      out.push({
        code: 'clothing_prop_' + sid,
        name: labelFor('prop', sid, s.drawable),
        slot_kind: 'prop', slot_id: sid,
        quantity: 1, unitWeight: 0,
      });
    }
    return out;
  }

  // -------------------------------------------------------------- tiles
  function invItemTile(item, opts) {
    const tile = el('li', 'inv__tile');
    if (opts && opts.readOnly) tile.classList.add('inv__tile--read-only');
    tile.appendChild(el('span', 'inv__tile-qty',
      item.quantity > 1 ? `x${item.quantity}` : ''));
    tile.appendChild(el('span', 'inv__tile-name',
      String(item.name || item.code)));
    tile.appendChild(el('span', 'inv__tile-weight',
      `${money(item.unitWeight || 0)} kg`));
    return tile;
  }

  // -------------------------------------------------------------- context menu
  // Right-click on a BACKPACK tile shows a small floating menu. Three
  // actions for V1:
  //   - Use      : Inventory.use (clothing_outfit routes through the
  //                 registered handler, so applying an outfit item from
  //                 here ends up at the same code path as the wardrobe's
  //                 "Anziehen").
  //   - Wegwerfen : Inventory.remove on this row.
  //   - Abbrechen : dismiss.
  //
  // The menu lives at the cursor position, dismisses on outside-click
  // or ESC. "Geben" (give-to-player) is intentionally absent in V1: it
  // needs a target-pick UI which is a separate concern.
  let menuState = null;

  function dismissMenu() {
    if (menuState && menuState.menu) {
      menuState.menu.remove();
      menuState = null;
    }
    document.removeEventListener('click', onDocClick, true);
  }

  function onDocClick(e) {
    if (menuState && menuState.menu && menuState.menu.contains(e.target)) return;
    dismissMenu();
  }
  function onKeyDown(e) {
    if (e.key === 'Escape') dismissMenu();
  }

  function showItemMenu(item, x, y) {
    dismissMenu();
    const menu = el('div', 'inv__menu');
    menu.style.left = x + 'px';
    menu.style.top  = y + 'px';

    const useBtn = el('button', 'inv__menu-item', 'Benutzen');
    useBtn.addEventListener('click', () => {
      dismissMenu();
      fetchNui('useItem', {
        code: item.code, quantity: 1, itemId: item.id,
      });
    });
    menu.appendChild(useBtn);

    const giveBtn = el('button', 'inv__menu-item', 'Geben');
    giveBtn.addEventListener('click', () => {
      dismissMenu();
      // Server arms give mode and returns the candidate list.
      fetchNui('enterGiveMode', {
        code: item.code, quantity: 1, itemId: item.id,
      }).then(({ ok, targets }) => {
        if (ok) showTargetPicker(item, targets || []);
      });
    });
    menu.appendChild(giveBtn);

    const dropBtn = el('button', 'inv__menu-item', 'Wegwerfen');
    dropBtn.addEventListener('click', () => {
      dismissMenu();
      fetchNui('discardItemOnGround', {
        code: item.code, quantity: 1, itemId: item.id,
      });
    });
    menu.appendChild(dropBtn);

    const cancelBtn = el('button', 'inv__menu-item inv__menu-item--cancel',
      'Abbrechen');
    cancelBtn.addEventListener('click', dismissMenu);
    menu.appendChild(cancelBtn);

    document.body.appendChild(menu);
    menuState = { menu, item };

    setTimeout(() => {
      document.addEventListener('click', onDocClick, true);
      document.addEventListener('keydown', onKeyDown);
    }, 0);
  }

  // -------------------------------------------------------------- target picker
  // Modal overlay listing nearby players the giver can pick. Click on
  // a row -> confirmGive to the server. The overlay dismisses either
  // on a successful transfer or on the Abbrechen button.
  let targetPickerState = null;

  function dismissTargetPicker() {
    if (targetPickerState && targetPickerState.overlay) {
      targetPickerState.overlay.remove();
      targetPickerState = null;
    }
  }

  function showTargetPicker(item, targets) {
    dismissTargetPicker();

    const overlay = el('div', 'inv__target-picker');
    const title = el('div', 'inv__target-picker__title',
      `An wen: ${item.name || item.code}`);
    overlay.appendChild(title);

    const list = el('div', 'inv__target-picker__list');

    if (!targets.length) {
      list.appendChild(el('div', 'inv__target-empty',
        'Keine Spieler in Reichweite.'));
    } else {
      for (const t of targets) {
        const row = el('button', 'inv__target-row');
        row.appendChild(el('span', 'inv__target-row__name', t.name));
        row.appendChild(el('span', 'inv__target-row__dist',
          t.distance.toFixed(1) + ' m'));
        row.addEventListener('click', () => {
          fetchNui('confirmGive', { targetSrc: t.src }).then(({ ok }) => {
            dismissTargetPicker();
            if (ok) {
              const note = el('div', 'inv__target-success',
                `An ${t.name} gegeben.`);
              overlay.innerHTML = '';
              overlay.appendChild(note);
              setTimeout(dismissTargetPicker, 1500);
            }
          });
        });
        list.appendChild(row);
      }
    }

    const cancel = el('button', 'inv__target-cancel', 'Abbrechen');
    cancel.addEventListener('click', () => {
      dismissTargetPicker();
      fetchNui('exitGiveMode');
    });
    overlay.appendChild(list);
    overlay.appendChild(cancel);

    document.body.appendChild(overlay);
    targetPickerState = { overlay };

    // Background click on the overlay (not on the modal contents)
    // dismisses. The list covers most of the surface so this is
    // mostly the user clicking outside the cancel button.
    overlay.addEventListener('click', (e) => {
      if (e.target === overlay) {
        dismissTargetPicker();
        fetchNui('exitGiveMode');
      }
    });
  }

  // -------------------------------------------------------------- NUI bridge
  async function fetchNui(name, body) {
    try {
      const res = await fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(body || {}),
      });
      if (!res.ok) return null;
      return await res.json();
    } catch (_) { /* ignore */ }
    return null;
  }

  // The NUI's only entry: render the panel. Refresh replace-wholesale.
  function renderPanel() {
    const root = $('root');
    if (!root) return;
    root.classList.remove('hidden');

    const panel = $('panel');
    panel.innerHTML = '';

    // ---- header / summary / settings cog
    const header = el('div', 'inv__header');
    header.appendChild(el('h2', 'inv__title', 'INVENTORY'));

    const summary = el('span', 'inv__summary',
      `${hud.inventory.usedSlots}/${hud.inventory.totalSlots} Plätze · ` +
      `${money(hud.inventory.usedWeight)}/${money(hud.inventory.maxWeight)} KG`);
    header.appendChild(summary);

    const cog = el('button', 'inv__cog', '⚙');
    cog.title = 'Inventar-Einstellungen';
    header.appendChild(cog);
    panel.appendChild(header);

    // ---- settings popover
    const settings = el('div', 'inv__settings hidden');
    const toggleRow = (label, key) => {
      const row = el('label', 'inv__settings-row');
      const cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.checked = !!invSettings[key];
      const lab = el('span', null, label);
      row.append(cb, lab);
      cb.addEventListener('change', () => {
        invSettings[key] = cb.checked;
        saveInvSettings();
        applyVisibility(sections);
      });
      return row;
    };
    settings.appendChild(toggleRow('Rucksack zeigen',     'showBackpack'));
    settings.appendChild(toggleRow('Outfit zeigen',       'showOutfit'));
    settings.appendChild(toggleRow('Quick Access zeigen', 'showQuickAccess'));
    settings.appendChild(toggleRow('Umgebung zeigen',     'showEnvironment'));
    panel.appendChild(settings);

    cog.addEventListener('click', (e) => {
      e.stopPropagation();
      settings.classList.toggle('hidden');
    });

    // ---- four sections
    const grid = el('div', 'inv__grid');
    panel.appendChild(grid);

    const sections = {
      backpack:    el('section', 'inv__section inv__section--backpack'),
      outfit:      el('section', 'inv__section inv__section--outfit'),
      quick:       el('section', 'inv__section inv__section--quick'),
      environment: el('section', 'inv__section inv__section--environment'),
    };
    Object.values(sections).forEach((s) => grid.appendChild(s));

    // BACKPACK
    sections.backpack.appendChild(el('div', 'inv__section-header', 'BACKPACK'));
    if (hud.inventory.items.length) {
      const list = el('ul', 'inv__list');
      for (const item of hud.inventory.items) {
        const tile = invItemTile(item);
        // left click - nothing for V1 (uses the right-click menu).
        // right click - show the menu. preventDefault stops the browser's
        // own menu from opening.
        tile.addEventListener('contextmenu', (e) => {
          e.preventDefault();
          showItemMenu(item, e.clientX, e.clientY);
        });
        list.appendChild(tile);
      }
      sections.backpack.appendChild(list);
    } else {
      sections.backpack.appendChild(el('p', 'inv__empty', 'Rucksack ist leer.'));
    }

    // OUTFIT
    sections.outfit.appendChild(el('div', 'inv__section-header', 'OUTFIT'));
    const worn = wornItemsFromAppearance(hud.character && hud.character.appearance);
    if (worn.length) {
      const list = el('ul', 'inv__list');
      for (const item of worn) list.appendChild(invItemTile(item, { readOnly: true }));
      sections.outfit.appendChild(list);
    } else {
      sections.outfit.appendChild(el('p', 'inv__empty', 'Kein Outfit gespeichert.'));
    }

    // QUICK ACCESS - 5 empty slots; future hotbar binding.
    sections.quick.appendChild(el('div', 'inv__section-header', 'QUICK ACCESS'));
    const qList = el('ul', 'inv__list inv__list--quick');
    for (let i = 1; i <= 5; i++) {
      const slot = el('li', 'inv__tile inv__tile--quick');
      slot.appendChild(el('span', 'inv__tile-index', String(i)));
      qList.appendChild(slot);
    }
    sections.quick.appendChild(qList);

    // ENVIRONMENT - placeholder for drop-to-world. Empty state for now.
    sections.environment.appendChild(el('div', 'inv__section-header', 'ENVIRONMENT'));
    sections.environment.appendChild(
      el('p', 'inv__empty', 'Noch nichts abgelegt.'));

    applyVisibility(sections);
  }

  function clearPanel() {
    const root = $('root');
    if (!root) return;
    const panel = $('panel');
    if (panel) panel.innerHTML = '';
    root.classList.add('hidden');
    dismissMenu();
  }

  // -------------------------------------------------------------- close
  $('closeBtn').addEventListener('click', () => fetchNui('closePanel'));

  // -------------------------------------------------------------- lua -> js
  window.addEventListener('message', (e) => {
    const { action, data } = e.data || {};
    if (!action) return;
    if (action === 'open' || action === 'refresh') {
      if (data) {
        hud.inventory = data.inventory || hud.inventory;
        hud.character  = data.character  !== undefined ? data.character : hud.character;
      }
      renderPanel();
    } else if (action === 'close') {
      clearPanel();
    }
  });
})();
