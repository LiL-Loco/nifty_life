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
    faceGroups: { FACE_1D: [], FACE_2D: [] },
    parentNames: { mother: [], father: [] },
    componentLabels: {},
    propLabels: {},
    overlayLabels: {},
    zoneLabels: {},
    maxTexture: 80,
    hairOverlayState: 'unchecked',
    tattoos: { zones: null, byZone: {} },
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
    updateFaceBonesActive();
  };

  // Tell Lua whether the face-bone projection thread should be
  // ticking. The thread runs at 30 Hz and pushes bone positions to
  // the NUI; turning it on only when the player is in the
  // Gesichtszuege panel saves CPU.
  let _lastFaceBonesActive = null;
  const updateFaceBonesActive = () => {
    const top = state.panels[state.panels.length - 1];
    const want = !!(top && top.kind === 'faceFeatures');
    if (want === _lastFaceBonesActive) return;
    _lastFaceBonesActive = want;
    fetchNui('setFaceBonesActive', { active: want });
    if (!want) clearFaceDots();
  };

  const clearFaceDots = () => {
    const overlay = document.getElementById('faceOverlay');
    if (overlay) overlay.innerHTML = '';
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

  // ============================================================== face-bone dots
  // Each bone name is mapped to one or two face features (by axis).
  // Cheek bones map to FACE_1D entry id=0/1 (cheek width). Eyebrow
  // bones map to FACE_2D group "Augenbrauen" (id 7 and 6). Chin bones
  // to "Kinn" (id 17 and 15). etc. Drag direction (dx, dy in pixels)
  // is added to the current feature value (clamped to -1..1) and sent
  // as a setFeature. A single horizontal drag (dx dominant) maps to
  // the x-axis feature; vertical drag (dy dominant) maps to the y.
  const BONE_FEATURE_MAP = {
    'skel_l_cheek':           { x: 0 },   // FACE_1D Nasenbreite
    'skel_r_cheek':           { x: 0 },
    'skel_l_eyeball':         { y: 19 },  // FACE_1D Hals-Dicke (rough)
    'skel_r_eyeball':         { y: 19 },
    'skel_l_lip_lower_corner':{ x: 12 },  // FACE_1D Lippendicke
    'skel_r_lip_lower_corner':{ x: 12 },
    'skel_l_eyebrow_01':      { x: 7,  y: 6 },  // Brauen
    'skel_l_eyebrow_02':      { x: 7,  y: 6 },
    'skel_l_eyebrow_03':      { x: 7,  y: 6 },
    'skel_r_eyebrow_01':      { x: 7,  y: 6 },
    'skel_r_eyebrow_02':      { x: 7,  y: 6 },
    'skel_r_eyebrow_03':      { x: 7,  y: 6 },
    'skel_l_nose_01':         { y: 1 },   // Nasenboden
    'skel_l_nose_02':         { y: 1 },
    'skel_r_nose_01':         { y: 1 },
    'skel_r_nose_02':         { y: 1 },
    'skel_l_jawline_root':    { x: 13, y: 14 }, // Kiefer
    'skel_r_jawline_root':    { x: 13, y: 14 },
    'skel_l_chin_01':         { x: 17, y: 15 }, // Kinn
    'skel_l_chin_02':         { x: 17, y: 15 },
    'skel_l_chin_03':         { x: 17, y: 15 },
    'skel_r_chin_01':         { x: 17, y: 15 },
    'skel_r_chin_02':         { x: 17, y: 15 },
    'skel_r_chin_03':         { x: 17, y: 15 },
  };

  const renderFaceBones = (bones) => {
    if (!Array.isArray(bones) || bones.length === 0) return;
    const overlay = document.getElementById('faceOverlay');
    if (!overlay) return;
    overlay.innerHTML = '';
    const w = window.innerWidth;
    const h = window.innerHeight;
    for (const b of bones) {
      const dot = document.createElement('div');
      dot.className = 'cr-face-dot';
      dot.style.left = (b.x * w) + 'px';
      dot.style.top = (b.y * h) + 'px';
      const mapping = BONE_FEATURE_MAP[b.name];
      dot.dataset.bone = b.name;
      if (!mapping) { dot.style.display = 'none'; continue; }
      let startX = 0, startY = 0;
      let startValue = null;
      let pendingId = null, pendingValue = null;
      dot.addEventListener('mousedown', (e) => {
        e.preventDefault();
        e.stopPropagation();
        startX = e.clientX;
        startY = e.clientY;
        // Snapshot the current value of the dominant feature.
        const featureId = (Math.abs(e.clientX - startX) > Math.abs(e.clientY - startY))
          ? (mapping.x != null ? mapping.x : mapping.y)
          : (mapping.y != null ? mapping.y : mapping.x);
        const key = String(featureId);
        startValue = state.face.features[key] != null
          ? state.face.features[key]
          : 0.0;
        dot.classList.add('cr-face-dot--dragging');
      });
      window.addEventListener('mousemove', (e) => {
        if (startValue == null) return;
        const dx = (e.clientX - startX) / 200;  // 200px = full range
        const dy = (e.clientY - startY) / 200;
        // Map dominant axis to the feature the bone names suggest.
        const isHorizontal = Math.abs(dx) > Math.abs(dy);
        const fid = isHorizontal
          ? (mapping.x != null ? mapping.x : mapping.y)
          : (mapping.y != null ? mapping.y : mapping.x);
        const delta = isHorizontal ? dx : dy;
        const newValue = Math.max(-1.0, Math.min(1.0, startValue + delta));
        pendingId = fid;
        pendingValue = newValue;
      });
      window.addEventListener('mouseup', () => {
        if (startValue == null) return;
        if (pendingId != null) {
          fetchNui('setFeature', { id: pendingId, value: pendingValue });
        }
        startValue = null;
        pendingId = null;
        pendingValue = null;
        dot.classList.remove('cr-face-dot--dragging');
      });
      overlay.appendChild(dot);
    }
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

  // ============================================================ heritage
  const renderParents = () => {
    const root = el('div', '');
    const h = state.face.headBlend;
    const motherItems = state.labels.MOTHER || [];
    const fatherItems = state.labels.FATHER || [];
    const thirdItems  = state.labels.THIRDPERSON || [];

    // Heritage portraits. Each preset has a corresponding image file
    // in ui/images/<Name>.webp. The Mother/Father preset lists in
    // cl_labels.lua carry the names in the same order as the engine
    // head-blend presets, so the index from headBlend.mother / .father
    // maps 1:1 onto the image filenames.
    const motherNames = state.parentNames.mother || [];
    const fatherNames = state.parentNames.father || [];
    const motherName = motherNames[h.mother] || '';
    const fatherName = fatherNames[h.father] || '';

    const portraitRow = el('div', 'cr-heritage');
    const motherP = el('div', 'cr-heritage__portrait');
    motherP.appendChild(el('div', 'cr-heritage__label', 'Mutter'));
    const motherImg = el('img', '');
    motherImg.alt = motherItems[h.mother] || ('Mutter ' + h.mother);
    motherImg.src = motherName ? `images/${motherName}.webp` : '';
    motherImg.onerror = () => { motherImg.style.display = 'none'; };
    motherP.appendChild(motherImg);
    motherP.appendChild(el('div', 'cr-heritage__index', motherItems[h.mother] || ('Mutter ' + h.mother)));
    const fatherP = el('div', 'cr-heritage__portrait');
    fatherP.appendChild(el('div', 'cr-heritage__label', 'Vater'));
    const fatherImg = el('img', '');
    fatherImg.alt = fatherItems[h.father] || ('Vater ' + h.father);
    fatherImg.src = fatherName ? `images/${fatherName}.webp` : '';
    fatherImg.onerror = () => { fatherImg.style.display = 'none'; };
    fatherP.appendChild(fatherImg);
    fatherP.appendChild(el('div', 'cr-heritage__index', fatherItems[h.father] || ('Vater ' + h.father)));
    portraitRow.appendChild(motherP);
    portraitRow.appendChild(fatherP);
    root.appendChild(portraitRow);

    // 0..1 value list for resemblance and skin tone.
    const ZtO = [];
    for (let i = 0; i < 101; i++) ZtO.push((i / 100).toFixed(2));

    root.appendChild(separator('Personen'));
    root.appendChild(list('Mutter', motherItems, h.mother || 0, (i) => {
      fetchNui('setHeadBlend', { mother: i });
    }));
    root.appendChild(list('Vater', fatherItems, h.father || 0, (i) => {
      fetchNui('setHeadBlend', { father: i });
    }));
    if (thirdItems.length > 0) {
      root.appendChild(list('Dritte Person', thirdItems, h.third || 0, (i) => {
        fetchNui('setHeadBlend', { third: i });
      }));
    }

    root.appendChild(separator('Aehnlichkeit'));
    const resSlider = slider('Aehnlichkeit', ZtO,
      Math.floor((h.resemblance != null ? h.resemblance : 0.5) * 100),
      (i) => {
        const v = parseFloat(ZtO[i]) || 0;
        fetchNui('setHeadBlend', { resemblance: v });
      },
      (v) => parseFloat(v).toFixed(2));
    root.appendChild(resSlider);

    // Weight sliders: 21 entries (0..100% in 5% steps).
    const weightSteps = [];
    for (let p = 0; p <= 100; p += 5) weightSteps.push(p + ' %');
    const halfSteps = [];
    for (let p = 0; p <= 1000; p += 1) halfSteps.push((p / 10).toFixed(1) + ' %');
    root.appendChild(separator('Anteile'));
    root.appendChild(slider('Mutter-Anteil', halfSteps,
      Math.floor((h.motherWeight != null ? h.motherWeight : 0.5) * 1000),
      (i) => fetchNui('setHeadBlend', { motherWeight: (i / 1000) }),
      (v) => v + ' %'));
    root.appendChild(slider('Vater-Anteil', halfSteps,
      Math.floor((h.fatherWeight != null ? h.fatherWeight : 0.5) * 1000),
      (i) => fetchNui('setHeadBlend', { fatherWeight: (i / 1000) }),
      (v) => v + ' %'));
    root.appendChild(slider('Anteil dritte Person', halfSteps,
      Math.floor((h.thirdWeight != null ? h.thirdWeight : 0.0) * 1000),
      (i) => fetchNui('setHeadBlend', { thirdWeight: (i / 1000) }),
      (v) => v + ' %'));

    root.appendChild(separator('Hautton'));
    root.appendChild(slider('Hautton', ZtO,
      Math.floor((h.skinTone != null ? h.skinTone : 0.5) * 100),
      (i) => {
        const v = parseFloat(ZtO[i]) || 0;
        fetchNui('setHeadBlend', { skinTone: v });
      },
      (v) => parseFloat(v).toFixed(2)));
    return root;
  };

  const renderEyeColour = () => {
    const root = el('div', '');
    root.appendChild(separator('Augenfarbe'));
    const eyes = (state.labels.EYE_COLOURS || []).slice(0, 9);
    const cur = Math.min(state.face.eyeColour || 0, eyes.length - 1);
    root.appendChild(list('Augenfarbe', eyes, cur, (i) => {
      fetchNui('setEyeColour', { index: i });
    }));
    return root;
  };

  // ============================================================ face features
  // Each FACE_1D_GROUPS row is a 1D-H grid panel; each FACE_2D_GROUPS
  // row is a 2D grid panel. The 0..1 normalised position is converted
  // to engine -1..1 on the way out via toFeature().
  const isBinary = (v) => v == null || v <= -0.99 || v >= 0.99;

  const renderFaceFeatures = () => {
    const root = el('div', '');
    const groups1D = (state.faceGroups && state.faceGroups.FACE_1D) || [];
    const groups2D = (state.faceGroups && state.faceGroups.FACE_2D) || [];

    root.appendChild(separator('2D Merkmale'));
    for (const g of groups2D) {
      const xv = state.face.features[String(g.xId)] || 0;
      const yv = state.face.features[String(g.yId)] || 0;
      if (isBinary(xv) || isBinary(yv)) {
        if (!isBinary(xv)) {
          root.appendChild(grid1DH(g.title, g.left, g.right, fromFeature(xv),
            (p) => fetchNui('setFeature', { id: g.xId, value: toFeature(p) })));
        }
        if (!isBinary(yv)) {
          root.appendChild(grid1DH(g.title, g.top, g.bottom, fromFeature(yv),
            (p) => fetchNui('setFeature', { id: g.yId, value: toFeature(p) })));
        }
      } else {
        root.appendChild(grid2D(g.title, g.top, g.right, g.bottom, g.left,
          fromFeature(xv), fromFeature(yv),
          (px, py) => {
            fetchNui('setFeature', { id: g.xId, value: toFeature(px) });
            fetchNui('setFeature', { id: g.yId, value: toFeature(py) });
          }));
      }
    }

    root.appendChild(separator('1D Merkmale'));
    for (const g of groups1D) {
      const v = state.face.features[String(g.id)] || 0;
      root.appendChild(grid1DH(g.title, g.left, g.right, fromFeature(v),
        (p) => fetchNui('setFeature', { id: g.id, value: toFeature(p) })));
    }
    return root;
  };

  // ============================================================ hair
  const renderHair = () => {
    const root = el('div', '');
    const slot = (state.slots.components || {})[2] || [];
    if (slot.length === 0) {
      root.appendChild(el('div', 'cr-separator', 'Keine Frisuren geladen.'));
      return root;
    }
    const option = slot[0];
    const modelLabels = [];
    for (let d = 0; d < option.drawables; d++) {
      modelLabels.push('Frisur ' + (d + 1));
    }
    const cur = state.selection.components && state.selection.components['2'] || {};
    const drawable = Math.min(tonumber(cur.drawable) || 0, option.drawables - 1);

    root.appendChild(separator('Modell'));
    root.appendChild(list('Frisur', modelLabels, drawable, (i) => {
      fetchNui('setSlot', { kind: 'components', id: 2,
        slot: { collection: option.name, drawable: i, texture: 0 } });
    }));

    root.appendChild(separator('Hauptfarbe'));
    const pal = state.palettes.HAIR_PALETTE || [];
    root.appendChild(colourPicker('Hauptfarbe', pal, state.face.hairColour.primary || 0,
      (i) => fetchNui('setHairColour', { channel: 'primary', index: i })));

    root.appendChild(separator('Straehnen'));
    root.appendChild(colourPicker('Straehnen', pal, state.face.hairColour.highlight || 0,
      (i) => fetchNui('setHairColour', { channel: 'highlight', index: i })));

    const op = (state.face.hairOverlay && state.face.hairOverlay.opacity) || 1.0;
    const opLabels = [];
    for (let p = 0; p <= 100; p++) opLabels.push(p + ' %');
    root.appendChild(separator('Hair Fade'));
    root.appendChild(slider('Deckkraft', opLabels, Math.floor(op * 100), (i) => {
      fetchNui('setHairOverlayOpacity', { opacity: i / 100 });
    }, (v) => v + ' %'));
    return root;
  };

  // ============================================================ makeup
  const renderMakeup = () => {
    const root = el('div', '');
    root.appendChild(separator('Overlays'));
    for (let id = 0; id <= 9; id++) {
      const label = (state.overlayLabels && state.overlayLabels[id]) || ('Overlay ' + id);
      root.appendChild(button(label, 'Stil, Deckkraft und Farbe.', () => {
        pushPanel('overlay', { id });
      }));
    }
    return root;
  };

  const renderOverlay = (panel) => {
    const id = panel.payload && panel.payload.id;
    if (typeof id !== 'number') return el('div', '', 'Overlay fehlt.');
    const root = el('div', '');
    const label = (state.overlayLabels && state.overlayLabels[id]) || ('Overlay ' + id);

    // Build style list. Index 0 is "Keins" (off). Real styles from labels.
    const styles = ['Keins'];
    const realStyles = (state.labels.OVERLAY_STYLES && state.labels.OVERLAY_STYLES[String(id)]) || [];
    for (let i = 1; i < realStyles.length; i++) styles.push(realStyles[i] || ('Stil ' + i));

    const cur = state.face.overlays[String(id)] || { style: 0, opacity: 0, colourType: 1, colour: 0, secondColour: 0 };
    // The list index is (style + 1) if opacity > 0; else 1 (Keins).
    const startIdx = (cur.opacity > 0.01) ? Math.min(styles.length - 1, (cur.style || 0) + 1) : 0;

    root.appendChild(separator('Stil'));
    root.appendChild(list(label, styles, startIdx, (i) => {
      const newState = (i === 0)
        ? { style: 0, opacity: 0, colourType: 1, colour: 0, secondColour: 0 }
        : { style: i - 1, opacity: Math.max(cur.opacity || 0, 0.5), colourType: cur.colourType, colour: cur.colour, secondColour: cur.secondColour };
      fetchNui('setOverlay', { id, overlay: newState });
    }));

    // Opacity slider (0..100%).
    const opLabels = [];
    for (let p = 0; p <= 100; p++) opLabels.push(p + ' %');
    root.appendChild(separator('Deckkraft'));
    root.appendChild(slider('Deckkraft', opLabels,
      Math.floor((cur.opacity || 0) * 100),
      (i) => {
        const newState = { ...cur, opacity: i / 100 };
        fetchNui('setOverlay', { id, overlay: newState });
      }, (v) => v + ' %'));

    // Colour panel.
    const palettes = (state.palettes.OVERLAY_PALETTES || {})[id] || [];
    if (palettes.length > 0) {
      // If multiple palettes, offer a swap.
      if (palettes.length > 1) {
        const labels = palettes.map((p) => p[1] || 'Palette');
        const curPaletteIdx = palettes.findIndex((p) => p[0] === (cur.colourType || 1));
        const startPalIdx = curPaletteIdx >= 0 ? curPaletteIdx : 0;
        root.appendChild(separator('Farbpalette'));
        root.appendChild(list('Farbpalette', labels, startPalIdx, (i) => {
          fetchNui('swapOverlayPalette', { id, paletteIndex: i + 1 });
        }));
      }
      // Use the active palette based on colourType.
      const activePalette = palettes.find((p) => p[0] === (cur.colourType || 1)) || palettes[0];
      if (activePalette && activePalette[2] && activePalette[2].length > 0) {
        root.appendChild(separator('Farbe'));
        root.appendChild(colourPicker(activePalette[1] || 'Farbe', activePalette[2],
          Math.min(cur.colour || 0, activePalette[2].length - 1),
          (i) => {
            const newState = { ...cur, colour: i, secondColour: i };
            fetchNui('setOverlay', { id, overlay: newState });
          }));
      }
    }
    return root;
  };

  // ============================================================ outfit
  const renderOutfit = () => {
    const root = el('div', '');
    const compIds = Object.keys(state.slots.components || {})
      .map((s) => parseInt(s, 10)).filter((n) => !isNaN(n)).sort((a, b) => a - b);
    const propIds = Object.keys(state.slots.props || {})
      .map((s) => parseInt(s, 10)).filter((n) => !isNaN(n)).sort((a, b) => a - b);

    root.appendChild(separator('Kleidung'));
    for (const id of compIds) {
      if (id === 2) continue; // hair lives in the Haare category
      const label = (state.componentLabels && state.componentLabels[id]) || ('Slot ' + id);
      const opt = (state.slots.components[String(id)] || [])[0];
      const count = opt ? opt.drawables : 0;
      root.appendChild(button(label, `Slot ${id} - ${count} Kollektionen`, () => {
        pushPanel('slot', { kind: 'components', id });
      }));
    }
    if (propIds.length > 0) {
      root.appendChild(separator('Accessoires'));
      for (const id of propIds) {
        const label = (state.propLabels && state.propLabels[id]) || ('Prop ' + id);
        const opt = (state.slots.props[String(id)] || [])[0];
        const count = opt ? opt.drawables : 0;
        root.appendChild(button(label, `Prop ${id} - ${count} Kollektionen`, () => {
          pushPanel('slot', { kind: 'props', id });
        }));
      }
    }
    // Body overlays.
    const maxOverlay = (state.overlayLabels && Object.keys(state.overlayLabels).length) || 12;
    root.appendChild(separator('Koerperfarbe'));
    for (let id = 10; id <= maxOverlay; id++) {
      const label = (state.overlayLabels && state.overlayLabels[id]) || ('Overlay ' + id);
      root.appendChild(button(label, 'Stil und Deckkraft.', () => {
        pushPanel('overlay', { id });
      }));
    }
    return root;
  };

  // ============================================================ slot
  const renderSlot = (panel) => {
    const { kind, id } = panel.payload || {};
    if (!kind || typeof id !== 'number') return el('div', '', 'Slot fehlt.');
    const root = el('div', '');
    const slot = (state.slots[kind] || {})[String(id)] || [];
    if (slot.length === 0) {
      root.appendChild(el('div', 'cr-separator', 'Keine Stuecke verfuegbar.'));
      return root;
    }
    const option = slot[0];
    const label = (kind === 'props'
      ? (state.propLabels && state.propLabels[id]) || ('Prop ' + id)
      : (state.componentLabels && state.componentLabels[id]) || ('Slot ' + id));

    const cur = (state.selection[kind] || {})[String(id)] || {};
    const drawable = Math.min(tonumber(cur.drawable) || 0, option.drawables - 1);
    const texture = Math.min(tonumber(cur.texture) || 0, Math.max(1, option.textures) - 1);

    // Modell list.
    const modelLabels = [];
    for (let d = 0; d < option.drawables; d++) {
      modelLabels.push('Modell ' + (d + 1));
    }
    root.appendChild(separator('Modell'));
    root.appendChild(list('Modell', modelLabels, drawable, (i) => {
      fetchNui('setSlot', { kind, id, slot: { collection: option.name, drawable: i, texture } });
    }));

    // Ausfuehrung list.
    const texLabels = [];
    for (let t = 0; t < option.textures; t++) {
      texLabels.push('Ausfuehrung ' + (t + 1));
    }
    root.appendChild(separator('Ausfuehrung'));
    root.appendChild(list('Ausfuehrung', texLabels, texture, (i) => {
      fetchNui('setSlot', { kind, id, slot: { collection: option.name, drawable, texture: i } });
    }));
    return root;
  };

  // ============================================================ tattoos
  const renderTattoos = () => {
    const root = el('div', '');
    root.appendChild(separator('Lade Zonen...'));
    // Lazy fetch on first render.
    fetchNui('getTattooZones').then(() => {
      // The reply comes in via 'tattooZones' action; the message handler
      // updates state.tattoos.zones. We re-render after a short delay.
    });
    // Optimistic: also render zones from cache if available.
    if (state.tattoos && state.tattoos.zones) {
      root.innerHTML = '';
      for (const zoneId of state.tattoos.zones) {
        const label = (state.zoneLabels && state.zoneLabels[zoneId]) || ('Zone ' + zoneId);
        root.appendChild(button(label, null, () => {
          pushPanel('tattooZone', { zoneId });
        }));
      }
    }
    return root;
  };

  const renderTattooZone = (panel) => {
    const zoneId = panel.payload && panel.payload.zoneId;
    if (typeof zoneId !== 'number') return el('div', '', 'Zone fehlt.');
    const root = el('div', '');
    const label = (state.zoneLabels && state.zoneLabels[zoneId]) || ('Zone ' + zoneId);

    // Keins button.
    root.appendChild(button('Keins', 'Alle Tattoos dieser Zone entfernen.', () => {
      fetchNui('removeTattoo', { zoneId });
    }));

    // Lazy fetch.
    fetchNui('getTattoosByZone', { zoneId });
    const cached = state.tattoos && state.tattoos.byZone && state.tattoos.byZone[zoneId];
    if (cached && cached.length > 0) {
      root.appendChild(separator(label));
      for (const t of cached) {
        root.appendChild(button(t.name || t.collection, t.collection, () => {
          fetchNui('pickTattoo', { zoneId, collection: t.collection, preset: t.preset });
        }));
      }
    } else {
      root.appendChild(separator('Lade Tattoos...'));
    }
    return root;
  };

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
      case 'tattooZones':
        if (data && data.zones) {
          state.tattoos.zones = data.zones;
          renderActive();
        }
        break;
      case 'tattoosByZone':
        if (data && typeof data.zoneId === 'number') {
          state.tattoos.byZone[data.zoneId] = data.tattoos || [];
          renderActive();
        }
        break;
      case 'faceBones':
        renderFaceBones(data && data.bones);
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
    if (data.faceGroups) state.faceGroups = data.faceGroups;
    if (data.parentNames) state.parentNames = data.parentNames;
    if (data.componentLabels) state.componentLabels = data.componentLabels;
    if (data.propLabels) state.propLabels = data.propLabels;
    if (data.overlayLabels) state.overlayLabels = data.overlayLabels;
    if (data.zoneLabels) state.zoneLabels = data.zoneLabels;
    if (data.maxTexture) state.maxTexture = data.maxTexture;
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
