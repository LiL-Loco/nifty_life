// Nifty Creator — NUI client
// Single-page panel-stack. Lua has authoritative state; NUI receives
// pushes via 'open' / 'refresh' / 'close' and posts back via fetch NUI.

(() => {
  'use strict';

  // ---------------------------------------------------------------- helpers
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

  // Convert normalised 0..1 to engine -1..1 (snap to 0.01).
  const toFeature = (posX) => {
    const v = (posX || 0.5) * 2 - 1;
    return Math.floor(v * 100 + 0.5) / 100;
  };
  const fromFeature = (v) => (v == null ? 0.5 : (v + 1) / 2);
  const frac = (index, n) => (index - 1) / (n - 1);

  // ---------------------------------------------------------------- state
  const state = {
    open: false,
    currentModel: 'mp_m_freemode_01',
    characterGender: 'male',
    skinCam: 'body',
    modelIsUndecided: false,
    face: { features: {}, overlays: {}, hairColour: { primary: 0, highlight: 0 },
            hairOverlay: null, tattoos: [], eyeColour: 0,
            headBlend: { mother: 21, father: 0, third: 21, motherWeight: 0.5,
                         fatherWeight: 0.5, thirdWeight: 0.0, skinTone: 0.5 } },
    selection: { components: {}, props: {} },
    slots: { components: {}, props: {} },
    scene: null,
    labels: { FEATURES: [], OVERLAY_STYLES: {}, EYE_COLOURS: [],
              MOTHER: [], FATHER: [], THIRDPERSON: [], OVERLAY_LABELS: {},
              ZONE_LABELS: {}, PROP_LABELS: {}, COMPONENT_LABELS: {} },
    palettes: { HAIR_PALETTE: [], MAKEUP_PALETTE: [], OVERLAY_PALETTES: {} },
    hairOverlayState: 'unchecked',
    panels: [],
    panelIdCounter: 0,
    parentsMode: null,    // 'face' when face category is open
    boneDots: [],
    boneDragId: null,
  };

  const newPanelId = () => `p${++state.panelIdCounter}`;

  // ---------------------------------------------------------------- panel stack
  const pushPanel = (kind, payload) => {
    state.panels.push({
      id: newPanelId(),
      kind, payload, scroll: 0, focusRow: 0,
    });
    renderActive();
  };

  const popPanel = () => {
    if (state.panels.length <= 1) return false;
    state.panels.pop();
    renderActive();
    return true;
  };

  const replacePanel = (kind, payload) => {
    if (state.panels.length > 0) {
      state.panels[state.panels.length - 1] = {
        id: newPanelId(), kind, payload, scroll: 0, focusRow: 0,
      };
    } else {
      state.panels.push({ id: newPanelId(), kind, payload, scroll: 0, focusRow: 0 });
    }
    renderActive();
  };

  const closeAll = () => fetchNui('closePanel');

  // ---------------------------------------------------------------- render
  const stack = () => document.getElementById('panelStack');

  const renderActive = () => {
    const root = document.getElementById('root');
    if (!root) return;
    const stackEl = stack();
    if (!stackEl) return;
    stackEl.innerHTML = '';
    const panel = state.panels[state.panels.length - 1];
    if (!panel) return;
    const dom = renderPanel(panel);
    if (dom) {
      dom.classList.add('cr-panel');
      stackEl.appendChild(dom);
    }
    updateSubtitle();
    updateSkinCamHint();
  };

  const updateSubtitle = () => {
    const sub = document.getElementById('subtitle');
    if (!sub) return;
    const panel = state.panels[state.panels.length - 1];
    if (!panel) { sub.textContent = 'Aussehen - Name und Stammdaten stehen bereits fest.'; return; }
    sub.textContent = panelSubtitle(panel) || sub.dataset.default || 'Aussehen - Name und Stammdaten stehen bereits fest.';
  };

  const updateSkinCamHint = () => {
    const hint = document.getElementById('skinCamHint');
    if (!hint) return;
    const panel = state.panels[state.panels.length - 1];
    const facePanels = new Set(['faceFeatures', 'parents', 'hair', 'makeup']);
    if (panel && facePanels.has(panel.kind)) {
      hint.classList.remove('hidden');
    } else {
      hint.classList.add('hidden');
    }
  };

  const panelSubtitle = (panel) => {
    if (panel.kind === 'parents') return parentsSummary();
    if (panel.kind === 'faceFeatures') return 'Ziehen, um das Gesicht zu formen.';
    if (panel.kind === 'hair') return 'Frisur und Haarfarbe.';
    if (panel.kind === 'makeup') return 'Stil, Deckkraft und Farbe.';
    if (panel.kind === 'tattoos') return 'Tattoos pro Koerperzone.';
    if (panel.kind === 'outfit') return 'Kleidung, Accessoires und Koerperfarbe.';
    if (panel.kind === 'root') return state.modelIsUndecided
      ? 'Waehle ein Modell.'
      : 'Aussehen - Name und Stammdaten stehen bereits fest.';
    return '';
  };

  const parentsSummary = () => {
    const h = state.face.headBlend;
    const wm = h.motherWeight || 0, wf = h.fatherWeight || 0, wc = h.thirdWeight || 0;
    const total = wm + wf + wc;
    if (total <= 0) return 'Ergebnis: alle drei Anteile 0 %.';
    return `Ergebnis: Mutter ${(wm / total * 100).toFixed(0)} %, Vater ${(wf / total * 100).toFixed(0)} %, dritte Person ${(wc / total * 100).toFixed(0)} %`;
  };

  // The placeholder for panel rendering; real implementations come next.
  const renderPanel = (panel) => {
    switch (panel.kind) {
      case 'root': return renderRoot(panel);
      case 'heritage': return renderHeritageCategory(panel);
      case 'parents': return renderParents(panel);
      case 'eyeColour': return renderEyeColour(panel);
      case 'faceFeatures': return renderFaceFeatures(panel);
      case 'hair': return renderHair(panel);
      case 'makeup': return renderMakeup(panel);
      case 'overlay': return renderOverlay(panel);
      case 'outfit': return renderOutfit(panel);
      case 'slot': return renderSlot(panel);
      case 'tattoos': return renderTattoos(panel);
      case 'tattooZone': return renderTattooZone(panel);
      default: return el('div', 'cr-panel', 'Unbekanntes Panel: ' + panel.kind);
    }
  };

  // ============================================================== widgets
  const button = (label, desc, onClick, opts = {}) => {
    const b = el('button', 'cr-btn');
    const left = el('div', 'cr-btn__left');
    left.appendChild(el('div', 'cr-btn__label', label));
    if (desc) left.appendChild(el('div', 'cr-btn__desc', desc));
    b.appendChild(left);
    if (opts.chevron !== false) b.appendChild(el('span', 'cr-btn__chevron', '›'));
    if (opts.danger) b.classList.add('cr-btn--danger');
    if (opts.primary) b.classList.add('cr-btn--primary');
    if (opts.disabled) b.disabled = true;
    b.addEventListener('click', onClick);
    return b;
  };

  const separator = (label) => el('div', 'cr-separator', label);

  const list = (label, items, index, onChange, formatValue) => {
    const wrap = el('div', 'cr-list');
    const btnPrev = el('button', 'cr-list__btn', '‹');
    const disp = el('div', 'cr-list__display');
    disp.appendChild(el('span', 'cr-list__label', label));
    const valEl = el('span', 'cr-list__value',
      formatValue ? formatValue(items[index]) : items[index]);
    disp.appendChild(valEl);
    const btnNext = el('button', 'cr-list__btn', '›');
    wrap.appendChild(btnPrev);
    wrap.appendChild(disp);
    wrap.appendChild(btnNext);

    let cur = index;
    const refresh = () => {
      valEl.textContent = formatValue ? formatValue(items[cur]) : items[cur];
      btnPrev.disabled = cur <= 0;
      btnNext.disabled = cur >= items.length - 1;
    };
    refresh();
    btnPrev.addEventListener('click', () => {
      if (cur <= 0) return;
      cur--;
      refresh();
      onChange(cur);
    });
    btnNext.addEventListener('click', () => {
      if (cur >= items.length - 1) return;
      cur++;
      refresh();
      onChange(cur);
    });
    wrap._getValue = () => cur;
    return wrap;
  };

  const slider = (label, valueLabels, index, onChange, formatValue) => {
    const wrap = el('div', 'cr-slider');
    const header = el('div', 'cr-slider__header');
    header.appendChild(el('span', 'cr-slider__label', label));
    const valEl = el('span', 'cr-slider__value',
      formatValue ? formatValue(valueLabels[index]) : valueLabels[index]);
    header.appendChild(valEl);
    wrap.appendChild(header);
    const bar = el('div', 'cr-slider__bar');
    const fill = el('div', 'cr-slider__fill');
    const thumb = el('div', 'cr-slider__thumb');
    bar.appendChild(fill);
    bar.appendChild(thumb);
    wrap.appendChild(bar);

    let cur = index;
    const refresh = () => {
      valEl.textContent = formatValue ? formatValue(valueLabels[cur]) : valueLabels[cur];
      const pct = (cur / Math.max(1, valueLabels.length - 1)) * 100;
      fill.style.width = pct + '%';
      thumb.style.left = pct + '%';
    };
    refresh();

    let dragging = false;
    const stepFromEvent = (e) => {
      const rect = bar.getBoundingClientRect();
      const x = (e.clientX != null ? e.clientX : (e.touches && e.touches[0].clientX)) - rect.left;
      const t = Math.max(0, Math.min(1, x / rect.width));
      const newIdx = Math.round(t * (valueLabels.length - 1));
      if (newIdx !== cur) {
        cur = newIdx;
        refresh();
        onChange(cur);
      }
    };
    bar.addEventListener('mousedown', (e) => { dragging = true; stepFromEvent(e); });
    window.addEventListener('mousemove', (e) => { if (dragging) stepFromEvent(e); });
    window.addEventListener('mouseup', () => { dragging = false; });
    wrap._getValue = () => cur;
    return wrap;
  };

  const colourPicker = (label, palette, index, onChange) => {
    const wrap = el('div', 'cr-colour');
    const header = el('div', 'cr-colour__header');
    header.appendChild(el('span', 'cr-colour__label', label));
    const preview = el('div', 'cr-colour__preview');
    header.appendChild(preview);
    wrap.appendChild(header);
    const strip = el('div', 'cr-colour__strip');
    wrap.appendChild(strip);

    const setPreview = (rgba) => {
      preview.style.background = `rgba(${rgba[0]}, ${rgba[1]}, ${rgba[2]}, ${rgba[3] / 255})`;
    };
    const swatches = [];
    let cur = index;
    palette.forEach((rgba, i) => {
      const s = el('button', 'cr-colour__swatch');
      s.type = 'button';
      s.style.background = `rgba(${rgba[0]}, ${rgba[1]}, ${rgba[2]}, ${rgba[3] / 255})`;
      s.title = `Farbe ${i + 1}`;
      s.addEventListener('click', () => {
        swatches.forEach((sw, j) => sw.classList.toggle('cr-colour__swatch--active', j === i));
        cur = i;
        setPreview(rgba);
        onChange(i);
      });
      strip.appendChild(s);
      swatches.push(s);
    });
    if (cur >= 0 && cur < swatches.length) swatches[cur].classList.add('cr-colour__swatch--active');
    if (cur >= 0 && palette[cur]) setPreview(palette[cur]);
    wrap._getValue = () => cur;
    return wrap;
  };

  const grid1DH = (label, left, right, posX, onChange) => {
    const wrap = el('div', 'cr-grid cr-grid-1d-h');
    const lbl = el('div', 'cr-grid__label');
    lbl.appendChild(el('span', '', label));
    const valEl = el('span', 'cr-grid__value', ((posX || 0.5) * 100).toFixed(0) + ' %');
    lbl.appendChild(valEl);
    wrap.appendChild(lbl);
    const track = el('div', 'cr-grid-1d-h__track');
    const fill = el('div', 'cr-grid-1d-h__fill');
    const cursor = el('div', 'cr-grid-1d-h__cursor');
    track.appendChild(fill);
    track.appendChild(cursor);
    wrap.appendChild(track);
    const ends = el('div', 'cr-grid-1d-h__ends');
    ends.appendChild(el('span', '', left || ''));
    ends.appendChild(el('span', '', right || ''));
    wrap.appendChild(ends);

    let cur = Math.max(0, Math.min(1, posX || 0.5));
    const refresh = () => {
      const pct = cur * 100;
      fill.style.width = pct + '%';
      cursor.style.left = pct + '%';
      valEl.textContent = pct.toFixed(0) + ' %';
    };
    refresh();

    let dragging = false;
    const stepFromEvent = (e) => {
      const rect = track.getBoundingClientRect();
      const cx = (e.clientX != null ? e.clientX : (e.touches && e.touches[0].clientX)) - rect.left;
      cur = Math.max(0, Math.min(1, cx / rect.width));
      refresh();
      onChange(cur);
    };
    track.addEventListener('mousedown', (e) => { dragging = true; stepFromEvent(e); });
    window.addEventListener('mousemove', (e) => { if (dragging) stepFromEvent(e); });
    window.addEventListener('mouseup', () => { dragging = false; });
    wrap._getValue = () => cur;
    return wrap;
  };

  const grid1DV = (label, top, bottom, posY, onChange) => {
    const wrap = el('div', 'cr-grid cr-grid-1d-v');
    const lbl = el('div', 'cr-grid__label');
    lbl.appendChild(el('span', '', label));
    const valEl = el('span', 'cr-grid__value', ((posY || 0.5) * 100).toFixed(0) + ' %');
    lbl.appendChild(valEl);
    wrap.appendChild(lbl);
    const track = el('div', 'cr-grid-1d-v__track');
    const fill = el('div', 'cr-grid-1d-v__fill');
    const cursor = el('div', 'cr-grid-1d-v__cursor');
    track.appendChild(fill);
    track.appendChild(cursor);
    wrap.appendChild(track);
    const ends = el('div', 'cr-grid-1d-v__ends');
    ends.appendChild(el('span', '', top || ''));
    ends.appendChild(el('span', '', bottom || ''));
    wrap.appendChild(ends);

    let cur = Math.max(0, Math.min(1, posY || 0.5));
    const refresh = () => {
      const pct = cur * 100;
      fill.style.height = pct + '%';
      cursor.style.top = pct + '%';
      valEl.textContent = pct.toFixed(0) + ' %';
    };
    refresh();

    let dragging = false;
    const stepFromEvent = (e) => {
      const rect = track.getBoundingClientRect();
      const cy = (e.clientY != null ? e.clientY : (e.touches && e.touches[0].clientY)) - rect.top;
      cur = Math.max(0, Math.min(1, cy / rect.height));
      refresh();
      onChange(cur);
    };
    track.addEventListener('mousedown', (e) => { dragging = true; stepFromEvent(e); });
    window.addEventListener('mousemove', (e) => { if (dragging) stepFromEvent(e); });
    window.addEventListener('mouseup', () => { dragging = false; });
    wrap._getValue = () => cur;
    return wrap;
  };

  const grid2D = (label, topL, topR, bottomL, bottomR, posX, posY, onChange) => {
    const wrap = el('div', 'cr-grid cr-grid-2d');
    const lbl = el('div', 'cr-grid__label');
    lbl.appendChild(el('span', '', label));
    const valEl = el('span', 'cr-grid__value',
      `${((posX || 0.5) * 100).toFixed(0)} / ${((posY || 0.5) * 100).toFixed(0)}`);
    lbl.appendChild(valEl);
    wrap.appendChild(lbl);
    const face = el('div', 'cr-grid-2d__face');
    const cursor = el('div', 'cr-grid-2d__cursor');
    face.appendChild(cursor);
    const quads = el('div', 'cr-grid-2d__quadrants');
    quads.appendChild(el('span', 'cr-grid-2d__q tl', topL || ''));
    quads.appendChild(el('span', 'cr-grid-2d__q tr', topR || ''));
    quads.appendChild(el('span', 'cr-grid-2d__q bl', bottomL || ''));
    quads.appendChild(el('span', 'cr-grid-2d__q br', bottomR || ''));
    face.appendChild(quads);
    wrap.appendChild(face);

    let cx = Math.max(0, Math.min(1, posX || 0.5));
    let cy = Math.max(0, Math.min(1, posY || 0.5));
    const refresh = () => {
      cursor.style.left = (cx * 100) + '%';
      cursor.style.top = (cy * 100) + '%';
      valEl.textContent = `${(cx * 100).toFixed(0)} / ${(cy * 100).toFixed(0)}`;
    };
    refresh();
    let dragging = false;
    const step = (e) => {
      const rect = face.getBoundingClientRect();
      const px = (e.clientX != null ? e.clientX : (e.touches && e.touches[0].clientX)) - rect.left;
      const py = (e.clientY != null ? e.clientY : (e.touches && e.touches[0].clientY)) - rect.top;
      cx = Math.max(0, Math.min(1, px / rect.width));
      cy = Math.max(0, Math.min(1, py / rect.height));
      refresh();
      onChange(cx, cy);
    };
    face.addEventListener('mousedown', (e) => { dragging = true; step(e); });
    window.addEventListener('mousemove', (e) => { if (dragging) step(e); });
    window.addEventListener('mouseup', () => { dragging = false; });
    wrap._getValue = () => ({ x: cx, y: cy });
    return wrap;
  };

  // ============================================================== panel impls
  // Each returns a DOM element. The wrappers (button, slider, etc.) are
  // local helpers; the panel renderers are the heavy lifters.

  const renderRoot = (panel) => {
    const root = el('div', '');
    if (state.modelIsUndecided) {
      root.appendChild(separator('Modell'));
      root.appendChild(button('Maennlich', 'mp_m_freemode_01',
        () => fetchNui('pickModel', { model: 'mp_m_freemode_01' })));
      root.appendChild(button('Weiblich', 'mp_f_freemode_01',
        () => fetchNui('pickModel', { model: 'mp_f_freemode_01' })));
    }
    root.appendChild(separator('Kategorien'));
    root.appendChild(button('Heritage', 'Eltern und Augenfarbe.', () => pushPanel('heritage', {})));
    root.appendChild(button('Gesichtszuege', 'Forme dein Gesicht.', () => pushPanel('faceFeatures', {})));
    root.appendChild(button('Haare', 'Frisur und Haarfarbe.', () => pushPanel('hair', {})));
    root.appendChild(button('Makeup', 'Bart, Make-up, Brauen.', () => pushPanel('makeup', {})));
    root.appendChild(button('Tattoos', 'Tattoos pro Koerperzone.', () => pushPanel('tattoos', {})));
    root.appendChild(button('Outfit', 'Kleidung und Accessoires.', () => pushPanel('outfit', {})));
    root.appendChild(separator('Aktionen'));
    root.appendChild(button('Zufallsaufzug', null, () => fetchNui('randomise')));
    root.appendChild(button('Zufallschar', null, () => fetchNui('randomiseAll')));
    root.appendChild(button('Zuruecksetzen', null, () => fetchNui('reset')));
    root.appendChild(button('Kamera naeher', null, () => fetchNui('zoomIn')));
    root.appendChild(button('Kamera weiter', null, () => fetchNui('zoomOut')));
    root.appendChild(button('Fertig', null, () => fetchNui('submit'), { primary: true }));
    root.appendChild(button('Abbrechen', null, () => fetchNui('cancel'), { danger: true }));
    return root;
  };

  // The remaining panel renderers come in the next phase. For now, a
  // placeholder so the menu stack still navigates without errors.
  const renderHeritageCategory = () => {
    const root = el('div', '');
    root.appendChild(separator('Kategorien'));
    root.appendChild(button('Eltern', 'Vater, Mutter und Mischungen.', () => pushPanel('parents', {})));
    root.appendChild(button('Augenfarbe', '9 realistische Farben.', () => pushPanel('eyeColour', {})));
    return root;
  };
  const renderParents = () => el('div', '', 'Eltern (folgt)');
  const renderEyeColour = () => el('div', '', 'Augenfarbe (folgt)');
  const renderFaceFeatures = () => el('div', '', 'Gesichtszuege (folgt)');
  const renderHair = () => el('div', '', 'Haare (folgt)');
  const renderMakeup = () => el('div', '', 'Makeup (folgt)');
  const renderOverlay = () => el('div', '', 'Overlay (folgt)');
  const renderOutfit = () => el('div', '', 'Outfit (folgt)');
  const renderSlot = () => el('div', '', 'Slot (folgt)');
  const renderTattoos = () => el('div', '', 'Tattoos (folgt)');
  const renderTattooZone = () => el('div', '', 'Tattoo-Zone (folgt)');

  // ---------------------------------------------------------------- keyboard
  document.addEventListener('keydown', (e) => {
    if (!state.open) return;
    const tag = (e.target && e.target.tagName) || '';
    if (['INPUT', 'TEXTAREA', 'SELECT'].includes(tag)) return;

    if (e.key === 'Escape') {
      e.preventDefault();
      if (document.querySelector('.cr-modal')) return; // modal owns ESC
      if (!popPanel()) closeAll();
      return;
    }
    if (e.key === 'q' || e.key === 'Q' || e.keyCode === 81) {
      fetchNui('camYaw', { delta: -1 });
      return;
    }
    if (e.key === 'e' || e.key === 'E' || e.keyCode === 69) {
      fetchNui('camYaw', { delta: 1 });
      return;
    }
    if (e.key === 'ArrowUp') {
      const top = state.panels[state.panels.length - 1];
      if (top && top.kind === 'root') { fetchNui('zoomIn'); e.preventDefault(); }
      return;
    }
    if (e.key === 'ArrowDown') {
      const top = state.panels[state.panels.length - 1];
      if (top && top.kind === 'root') { fetchNui('zoomOut'); e.preventDefault(); }
      return;
    }
  });

  // ---------------------------------------------------------------- close button
  const closeBtn = document.getElementById('closeBtn');
  if (closeBtn) closeBtn.addEventListener('click', closeAll);

  // ---------------------------------------------------------------- message handler
  window.addEventListener('message', (e) => {
    const { action, data } = e.data || {};
    if (!action) return;
    switch (action) {
      case 'open':
        applyOpen(data || {});
        break;
      case 'refresh':
        applyRefresh(data || {});
        break;
      case 'close':
        applyClose();
        break;
      case 'skinCam':
        if (data && data.kind) state.skinCam = data.kind;
        updateSkinCamHint();
        break;
      case 'error':
        toast(data && data.message, true);
        break;
      default:
        // No-op; other actions like 'tattooZones' / 'tattoosByZone' /
        // 'parentPortraits' / 'faceBones' are handled below as needed.
        break;
    }
  });

  const applyOpen = (data) => {
    state.open = true;
    if (data.currentModel) state.currentModel = data.currentModel;
    if (data.characterGender) state.characterGender = data.characterGender;
    if (data.scene) state.scene = data.scene;
    if (data.selection) state.selection = mergeSelection(state.selection, data.selection);
    if (data.face) state.face = mergeFace(state.face, data.face);
    if (data.slots) state.slots = data.slots;
    if (data.labels) state.labels = data.labels;
    if (data.palettes) state.palettes = data.palettes;
    if (data.hairOverlayState) state.hairOverlayState = data.hairOverlayState;
    if (typeof data.modelIsUndecided === 'boolean') state.modelIsUndecided = data.modelIsUndecided;
    if (data.skinCam) state.skinCam = data.skinCam;

    const root = document.getElementById('root');
    if (root) root.classList.remove('hidden');
    state.panels = [];
    pushPanel('root', {});
  };

  const applyRefresh = (data) => {
    if (data.selection) state.selection = mergeSelection(state.selection, data.selection);
    if (data.face) state.face = mergeFace(state.face, data.face);
    if (data.skinCam) state.skinCam = data.skinCam;
    if (data.slots) state.slots = data.slots;
    renderActive();
  };

  const applyClose = () => {
    state.open = false;
    state.panels = [];
    const root = document.getElementById('root');
    if (root) root.classList.add('hidden');
    const stackEl = stack();
    if (stackEl) stackEl.innerHTML = '';
  };

  const mergeSelection = (cur, next) => ({
    components: { ...(cur.components || {}), ...(next.components || {}) },
    props:      { ...(cur.props      || {}), ...(next.props      || {}) },
  });

  const mergeFace = (cur, next) => {
    const out = { ...cur, ...next };
    if (next.hairColour) out.hairColour = { ...(cur.hairColour || {}), ...next.hairColour };
    if (next.headBlend)  out.headBlend  = { ...(cur.headBlend  || {}), ...next.headBlend  };
    return out;
  };
})();
