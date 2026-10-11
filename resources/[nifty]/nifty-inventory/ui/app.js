// Nifty Life 2.0 — inventory panel UI.
//
// Lives in nifty-inventory/ui/, loaded by nifty-world's NUI as an extra
// <script>. The panel keeps its DOM IDs / CSS classes self-contained so
// removing it from nifty-world or moving it to a separate resource
// involves no rewiring beyond the <script src>.
//
// Functions are attached to `window` because they are referenced by
// nifty-world's panel builder (which lives in another script). Each
// function takes its dependencies as arguments so we do not rely on a
// shared mutable global.
//
// Persistence: per-player inventory UI settings live in localStorage
// under `nifty.inv.settings.v1`. The settings are intentionally
// per-client - the dashboard wants to be different on someone's
// laptop vs. their desktop.

(function () {
  'use strict';

  const invSettingsKey = 'nifty.inv.settings.v1';
  const invSettings = (() => {
    try {
      const raw = localStorage.getItem(invSettingsKey);
      if (raw) return JSON.parse(raw);
    } catch (_) { /* ignore */ }
    return {
      showBackpack:    true,
      showOutfit:      true,
      showQuickAccess: true,
      showEnvironment: true,
    };
  })();
  function saveInvSettings() {
    try { localStorage.setItem(invSettingsKey, JSON.stringify(invSettings)); }
    catch (_) { /* private mode / disabled storage */ }
  }

  // German slot labels for OUTFIT tiles. The wardrobe panel has the
  // full Price.labelOf lookup; this stays local to keep the inventory
  // panel independent of nifty-clothing's bootstrap.
  const COMPONENT_NAMES = {
    1: 'Maske', 2: 'Haar', 3: 'Oberkörper', 4: 'Hose', 5: 'Schuhe',
    6: 'Socken', 7: 'Jacke', 8: 'Unterhemd', 9: 'Krawatte',
    10: 'Gürtel', 11: 'Oberteil',
  };
  const PROP_NAMES = {
    0: 'Mütze', 1: 'Brille', 2: 'Ohrring', 3: 'Uhr', 4: 'Armband', 5: 'Ring',
  };

  // el('div', 'class', 'text') - local copy of nifty-world's helper,
  // duplicated to keep this panel self-contained. Future cross-resource
  // sharing of the helper is a separate decision.
  function el(tag, cls, text) {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined) node.textContent = text;
    return node;
  }
  function money(n) {
    const v = Number(n) || 0;
    return v.toLocaleString('de-DE', {
      minimumFractionDigits: v % 1 === 0 ? 0 : 2,
      maximumFractionDigits: 2,
    });
  }

  // Compose the outfit list out of the saved appearance. Worn items
  // are read-only here - tile click does not invoke the wardrobe's
  // Ablegen etc. The wardrobe panel handles those actions.
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
        quantity: 1, unitWeight: 0,
        slot_kind: 'component', slot_id: sid,
      });
    }
    for (const k of Object.keys(appearance.props || {})) {
      const sid = Number(k);
      const s = appearance.props[k];
      if (!s) continue;
      out.push({
        code: 'clothing_prop_' + sid,
        name: labelFor('prop', sid, s.drawable),
        quantity: 1, unitWeight: 0,
        slot_kind: 'prop', slot_id: sid,
      });
    }
    return out;
  }

  // One tile in an inventory grid.
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

  // The panel itself. Accepts the live `hud` snapshot from the parent
  // page (nifty-world's app.js) so we do not need cross-resource state.
  function panelInventory(hud) {
    const wrap = el('div', 'inv');

    // ---- header
    const header = el('div', 'inv__header');
    const title = el('h2', 'inv__title', 'INVENTORY');
    header.appendChild(title);

    const summary = el('span', 'inv__summary',
      `${hud.inventory.usedSlots}/${hud.inventory.totalSlots} Plätze · ` +
      `${money(hud.inventory.usedWeight)} / ` +
      `${money(hud.inventory.maxWeight)} KG`);
    header.appendChild(summary);

    const cog = el('button', 'inv__cog', '⚙');
    cog.title = 'Inventar-Einstellungen';
    header.appendChild(cog);
    wrap.appendChild(header);

    // ---- settings
    const settingsPanel = el('div', 'inv__settings hidden');
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
        applySectionVisibility();
      });
      return row;
    };
    settingsPanel.appendChild(toggleRow('Rucksack zeigen',     'showBackpack'));
    settingsPanel.appendChild(toggleRow('Outfit zeigen',       'showOutfit'));
    settingsPanel.appendChild(toggleRow('Quick Access zeigen', 'showQuickAccess'));
    settingsPanel.appendChild(toggleRow('Umgebung zeigen',     'showEnvironment'));
    wrap.appendChild(settingsPanel);

    cog.addEventListener('click', (e) => {
      e.stopPropagation();
      settingsPanel.classList.toggle('hidden');
    });

    // ---- grid
    const grid = el('div', 'inv__grid');
    wrap.appendChild(grid);

    const sections = {
      backpack:   el('section', 'inv__section inv__section--backpack'),
      outfit:     el('section', 'inv__section inv__section--outfit'),
      quick:      el('section', 'inv__section inv__section--quick'),
      environment: el('section', 'inv__section inv__section--environment'),
    };
    Object.values(sections).forEach((s) => grid.appendChild(s));

    // backpack
    sections.backpack.appendChild(el('div', 'inv__section-header', 'BACKPACK'));
    if (hud.inventory.items.length) {
      const list = el('ul', 'inv__list');
      for (const item of hud.inventory.items) list.appendChild(invItemTile(item));
      sections.backpack.appendChild(list);
    } else {
      sections.backpack.appendChild(
        el('p', 'inv__empty', 'Rucksack ist leer.'));
    }

    // outfit
    sections.outfit.appendChild(el('div', 'inv__section-header', 'OUTFIT'));
    const worn = wornItemsFromAppearance(hud.character && hud.character.appearance);
    if (worn.length) {
      const list = el('ul', 'inv__list');
      for (const item of worn) list.appendChild(invItemTile(item, { readOnly: true }));
      sections.outfit.appendChild(list);
    } else {
      sections.outfit.appendChild(
        el('p', 'inv__empty', 'Kein Outfit gespeichert.'));
    }

    // quick access - empty slots, future hotbar
    sections.quick.appendChild(el('div', 'inv__section-header', 'QUICK ACCESS'));
    const qList = el('ul', 'inv__list inv__list--quick');
    for (let i = 1; i <= 5; i++) {
      const slot = el('li', 'inv__tile inv__tile--quick');
      slot.appendChild(el('span', 'inv__tile-index', String(i)));
      qList.appendChild(slot);
    }
    sections.quick.appendChild(qList);

    // environment
    sections.environment.appendChild(el('div', 'inv__section-header', 'ENVIRONMENT'));
    sections.environment.appendChild(
      el('p', 'inv__empty', 'Noch nichts abgelegt.'));

    // apply visibility AFTER sections exist
    function applySectionVisibility() {
      sections.backpack.classList.toggle('hidden', !invSettings.showBackpack);
      sections.outfit.classList.toggle('hidden', !invSettings.showOutfit);
      sections.quick.classList.toggle('hidden', !invSettings.showQuickAccess);
      sections.environment.classList.toggle('hidden', !invSettings.showEnvironment);
    }
    applySectionVisibility();

    return wrap;
  }

  // Attach the entry points so nifty-world's panel builder can find
  // them. window.* assigns to the global object explicitly so the
  // cross-script handoff survives nifty-world using `const` for its
  // own globals (which would not normally leak to other scripts).
  window.__niftyInventory = window.__niftyInventory || {};
  window.__niftyInventory.panelInventory = panelInventory;
})();
