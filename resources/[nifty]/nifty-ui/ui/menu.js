/* nifty-ui/ui/menu.js
 *
 * Vanilla-JS NUI page for the nifty menu. Consumes zUI-v2's NUI event
 * format and renders the same nifty look the original in-house NUI had
 * (gold #d6b469 accent, blue header gradient, Pacifico title, Segoe UI
 * body). zUI-v2 sends:
 *   menu:show      {title, subtitle, description, theme, banner}
 *   menu:close     {}
 *   menu:loadItems {items: [...]}
 * The page sends back:
 *   menu:useItem {itemId, type, ...}
 *   menu:goBack  {}
 * via Nifty.nui (from base.js).
 *
 * The theme JSON drives CSS variables via a theme:load event the
 * theme_loader client script sends at resource start.
 */
(function () {
  'use strict';

  var root = document.getElementById('menuRoot');
  var titleEl = document.getElementById('menuTitle');
  var subtitleEl = document.getElementById('menuSubtitle');
  var sectionEl = document.getElementById('menuSection');
  var sectionNameEl = document.getElementById('menuSectionName');
  var sectionProgressEl = document.getElementById('menuSectionProgress');
  var listEl = document.getElementById('menuList');

  var state = {
    items: [],
    selectedIndex: -1,
    itemsByIndex: {},   // index -> item (zUI item objects have stable ids)
  };

  // ----- DOM helpers -----

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  function clear(node) { while (node.firstChild) node.removeChild(node.firstChild); }

  function setVisible(node, visible) {
    if (visible) node.classList.remove('hidden');
    else node.classList.add('hidden');
  }

  // ----- Rendering -----

  function renderItem(item, index) {
    var kind = item.type;
    var li;

    if (kind === 'separator') {
      li = el('li', 'menuItem menuItem--separator');
      li.appendChild(el('span', 'menuItem__label', item.label || ''));
      return li;
    }

    if (kind === 'button') {
      li = el('li', 'menuItem menuItem--button' + (item.disabled ? ' menuItem--disabled' : ''));
      if (item.submenu) li.classList.add('menuItem--has-submenu');
      var labelWrap = el('div', 'menuItem__col');
      labelWrap.appendChild(el('div', 'menuItem__label', item.label || ''));
      if (item.description) labelWrap.appendChild(el('span', 'menuItem__desc', item.description));
      li.appendChild(labelWrap);
      if (item.submenu) li.appendChild(el('span', 'menuItem__chev', '›'));
      if (item.styles && item.styles.LeftBadge) {
        li.appendChild(el('span', 'menuItem__icon', item.styles.LeftBadge));
      }
      if (item.styles && item.styles.RightLabel) {
        li.appendChild(el('span', 'menuItem__right', item.styles.RightLabel));
      }
      bindClick(li, index, function () { activateButton(item); });
      return li;
    }

    if (kind === 'checkbox') {
      li = el('li', 'menuItem menuItem--checkbox' + (item.state ? ' menuItem--on' : '') + (item.disabled ? ' menuItem--disabled' : ''));
      li.appendChild(el('span', 'menuItem__icon', item.state ? '✓' : ''));
      var labelWrap2 = el('div', 'menuItem__col');
      labelWrap2.appendChild(el('div', 'menuItem__label', item.label || ''));
      if (item.description) labelWrap2.appendChild(el('span', 'menuItem__desc', item.description));
      li.appendChild(labelWrap2);
      bindClick(li, index, function () { activateCheckbox(item); });
      return li;
    }

    if (kind === 'slider') {
      li = el('li', 'menuItem menuItem--slider' + (item.disabled ? ' menuItem--disabled' : ''));
      var labelWrap3 = el('div', 'menuItem__col');
      labelWrap3.appendChild(el('div', 'menuItem__label', item.label || ''));
      if (item.description) labelWrap3.appendChild(el('span', 'menuItem__desc', item.description));
      li.appendChild(labelWrap3);
      var slider = el('div', 'menuSlider');
      var track = el('div', 'menuSlider__track');
      var fill = el('div', 'menuSlider__fill');
      var pct = Math.max(0, Math.min(100, Number(item.percentage) || 0));
      fill.style.width = pct + '%';
      track.appendChild(fill);
      slider.appendChild(track);
      var valueText = (item.styles && item.styles.ShowPercentage) ? (pct + '%') : String(pct);
      slider.appendChild(el('span', 'menuSlider__value', valueText));
      li.appendChild(slider);
      bindClick(li, index, function (ev) { return onSliderClick(ev, item, li, fill, slider); });
      return li;
    }

    if (kind === 'list') {
      li = el('li', 'menuItem menuItem--list' + (item.disabled ? ' menuItem--disabled' : ''));
      var labelWrap4 = el('div', 'menuItem__col');
      labelWrap4.appendChild(el('div', 'menuItem__label', item.label || ''));
      if (item.description) labelWrap4.appendChild(el('span', 'menuItem__desc', item.description));
      li.appendChild(labelWrap4);
      // Show the currently-selected item as a right-hand text.
      var idx = Math.max(1, Math.min((item.items || []).length, Number(item.index) || 1)) - 1;
      var currentItemText = (item.items && item.items[idx] != null) ? String(item.items[idx].label || item.items[idx]) : '';
      li.appendChild(el('span', 'menuItem__right', currentItemText));
      bindClick(li, index, function () { activateList(item); });
      return li;
    }

    if (kind === 'textarea') {
      // The shim maps Menu.input -> zUI-v2 textarea; we render it as a
      // single-line <input> for the nifty look.
      li = el('li', 'menuItem menuItem--input' + (item.disabled ? ' menuItem--disabled' : ''));
      li.appendChild(el('div', 'menuItem__label', item.label || ''));
      var input = el('input', 'menuInput');
      input.type = 'text';
      input.value = (item.value != null) ? String(item.value) : '';
      if (item.placeholder) input.placeholder = String(item.placeholder);
      if (item.maxLength) input.maxLength = Number(item.maxLength);
      input.addEventListener('input', function () { activateInput(item, input.value); });
      input.addEventListener('keydown', function (ev) { ev.stopPropagation(); });
      li.appendChild(input);
      return li;
    }

    // Unknown kind: render as disabled button so the user can see the row
    // and we don't silently drop it.
    li = el('li', 'menuItem menuItem--button menuItem--disabled');
    var labelWrapX = el('div', 'menuItem__col');
    labelWrapX.appendChild(el('div', 'menuItem__label', (item.label || '') + '  [unhandled: ' + kind + ']'));
    li.appendChild(labelWrapX);
    return li;
  }

  function renderItems(items) {
    clear(listEl);
    state.items = items || [];
    state.itemsByIndex = {};
    state.selectedIndex = -1;
    for (var i = 0; i < state.items.length; i++) {
      var item = state.items[i];
      if (item && item.itemId != null) state.itemsByIndex[i] = item;
      var kind = item && item.type;
      if (kind === 'separator') continue;
      var node = renderItem(item, i);
      node.dataset.index = String(i);
      listEl.appendChild(node);
    }
    setSelected(0);
  }

  function setSelected(idx) {
    if (state.items.length === 0) { state.selectedIndex = -1; return; }
    var clickable = [];
    for (var i = 0; i < state.items.length; i++) {
      if (state.items[i] && state.items[i].type !== 'separator' && !state.items[i].disabled) clickable.push(i);
    }
    if (clickable.length === 0) return;
    var pos = clickable.indexOf(idx);
    if (pos === -1) idx = clickable[0];
    else if (idx > clickable[pos] && pos + 1 < clickable.length) idx = clickable[pos + 1];
    state.selectedIndex = idx;
    var nodes = listEl.querySelectorAll('.menuItem');
    for (var j = 0; j < nodes.length; j++) {
      var n = nodes[j];
      if (Number(n.dataset.index) === idx) n.classList.add('menuItem--selected');
      else n.classList.remove('menuItem--selected');
    }
  }

  // ----- Activation -----

  function bindClick(li, index, handler) {
    li.addEventListener('click', function (ev) { setSelected(index); handler(ev); });
    li.addEventListener('mousemove', function () { setSelected(index); });
  }

  function activateButton(item) {
    Nifty.nui('menu:useItem', { itemId: item.itemId, type: 'button', onSelected: true });
  }

  function activateCheckbox(item) {
    Nifty.nui('menu:useItem', { itemId: item.itemId, type: 'checkbox', onSelected: true });
  }

  function activateList(item) {
    // Cycle forward on Enter. The Lua shim fires onSelect with the new
    // index. For lists with N items, a single useItem with type 'list'
    // and onSelected=true is enough; zUI-v2's _manager.lua calls the
    // action with (true, false, index). We start from the current
    // index and increment.
    var n = (item.items || []).length;
    if (n === 0) return;
    var next = (Number(item.index) || 1) % n + 1;
    Nifty.nui('menu:useItem', { itemId: item.itemId, type: 'list', onSelected: true, index: next });
  }

  function activateInput(item, value) {
    // Per-keystroke. The shim updates the closure-bound value and forces
    // a re-render via zUI.UpdateItems; the next render shows the new
    // value. This keeps typing responsive without waiting for the 500ms
    // poll.
    Nifty.nui('menu:useItem', { itemId: item.itemId, type: 'textarea', value: String(value) });
  }

  function onSliderClick(ev, item, li, fill, slider) {
    // Convert x-offset within the slider track to a percentage and
    // dispatch a useItem with type 'slider' + percentageChange.
    var rect = slider.getBoundingClientRect();
    var pct = Math.round(((ev.clientX - rect.left) / rect.width) * 100);
    pct = Math.max(0, Math.min(100, pct));
    fill.style.width = pct + '%';
    Nifty.nui('menu:useItem', {
      itemId: item.itemId,
      type: 'slider',
      percentageChange: true,
      percentage: pct,
    });
  }

  // ----- Keyboard -----

  window.addEventListener('keydown', function (ev) {
    if (root.classList.contains('hidden')) return;
    var key = ev.key;

    if (key === 'Escape' || key === 'Backspace') {
      Nifty.nui('menu:goBack', {});
      ev.preventDefault();
      return;
    }

    if (key === 'ArrowDown') { setSelected(state.selectedIndex + 1); ev.preventDefault(); return; }
    if (key === 'ArrowUp') { setSelected(state.selectedIndex - 1); ev.preventDefault(); return; }

    if (key === 'Enter' || key === ' ') {
      var item = state.items[state.selectedIndex];
      if (item && !item.disabled) {
        if (item.type === 'button') activateButton(item);
        else if (item.type === 'checkbox') activateCheckbox(item);
        else if (item.type === 'list') activateList(item);
        else if (item.type === 'slider') {
          // Nudge by 5%
          var cur = Number(item.percentage) || 0;
          var dir = (key === ' ') ? 1 : 1;
          var next = Math.max(0, Math.min(100, cur + dir * (item.step || 5)));
          Nifty.nui('menu:useItem', { itemId: item.itemId, type: 'slider', percentageChange: true, percentage: next });
        }
      }
      ev.preventDefault();
      return;
    }

    if (key === 'ArrowRight') {
      var it = state.items[state.selectedIndex];
      if (it && it.type === 'slider' && !it.disabled) {
        var cur2 = Number(it.percentage) || 0;
        var next2 = Math.min(100, cur2 + (it.step || 5));
        Nifty.nui('menu:useItem', { itemId: it.itemId, type: 'slider', percentageChange: true, percentage: next2 });
        ev.preventDefault();
      }
      return;
    }

    if (key === 'ArrowLeft') {
      var it2 = state.items[state.selectedIndex];
      if (it2 && it2.type === 'slider' && !it2.disabled) {
        var cur3 = Number(it2.percentage) || 0;
        var next3 = Math.max(0, cur3 - (it2.step || 5));
        Nifty.nui('menu:useItem', { itemId: it2.itemId, type: 'slider', percentageChange: true, percentage: next3 });
        ev.preventDefault();
      }
      return;
    }
  });

  // ----- zUI-v2 NUI messages -----

  window.addEventListener('message', function (event) {
    var data = event.data;
    if (!data || !data.action) return;
    var payload = data.data;

    if (data.action === 'menu:show') {
      titleEl.textContent = payload.title || '';
      subtitleEl.textContent = payload.subtitle || '';
      setVisible(subtitleEl, !!payload.subtitle);
      root.dataset.dock = 'right';  // nifty always docks right
      setVisible(root, true);
    }
    else if (data.action === 'menu:close') {
      setVisible(root, false);
    }
    else if (data.action === 'menu:loadItems') {
      // The payload is the ITEMS table. zUI-v2 sends an object keyed
      // by numeric index (since UpdateItems does `ITEMS[itemIndex] = item`).
      var items = [];
      if (Array.isArray(payload)) items = payload;
      else if (payload && typeof payload === 'object') {
        // Convert keyed-by-index object to an array, preserving order.
        var keys = Object.keys(payload).map(Number).sort(function (a, b) { return a - b; });
        for (var i = 0; i < keys.length; i++) items.push(payload[keys[i]]);
      }
      renderItems(items);
    }
    else if (data.action === 'menu:setIndexHistory') {
      // zUI-v2 tracks the menu nav history internally; we don't need it.
    }
    else if (data.action === 'theme:load') {
      applyTheme(payload);
    }
  });

  function applyTheme(theme) {
    if (!theme || !theme.menu || !theme.menu.colors) return;
    var c = theme.menu.colors;
    var root2 = document.documentElement;
    if (c.primary) root2.style.setProperty('--accent', c.primary);
    if (c.background) {
      // zUI-v2 ships backgrounds as rgba(); CSS variable accepts it.
      root2.style.setProperty('--bg', c.background);
    }
    if (c.itemSelected) {
      // The dim variant is the selected-row's background. zUI-v2 only
      // ships the solid colour, so derive the dim by reading it as an
      // approximation: 0.18 alpha of primary over the existing bg.
      // We keep the variable for the row highlight; CSS uses --accent-dim
      // and falls back to a hardcoded tint if missing.
      root2.style.setProperty('--accent-dim', 'rgba(214, 180, 105, 0.18)');
    }
    if (theme.menu.font) {
      // We don't swap fonts dynamically (Pacifico + Segoe UI is hardcoded
      // in menu.html for performance), but we set the variable so a
      // future CSS that uses var(--menu-font) can pick it up.
      root2.style.setProperty('--menu-font', theme.menu.font);
    }
  }

  // ----- Init -----

  // zUI-v2 may also send a menu:closed callback when the page closes
  // itself. We don't act on it; the menu:close message is the trigger.
  // Listen but no-op.

  // Expose a tiny global for the F8 console and for any debug helpers.
  window.NiftyMenu = { state: state, renderItems: renderItems };
})();
