// nifty-armwrestling / ui
//
// Receives hand-position ticks from the client and slides the dot along
// the bar. The client decides when to show / hide the bar (we only listen).
//
// Message shape:
//   { type: "show" }
//   { type: "hide" }
//   { type: "tick", pos: 0..1 }   // 0 = left lost, 0.5 = centre, 1 = right lost

(() => {
  const bar = document.getElementById('bar');
  const dot = document.getElementById('dot');
  if (!bar || !dot) return;

  window.addEventListener('message', (e) => {
    const m = e.data;
    if (!m || !m.type) return;
    if (m.type === 'show') {
      bar.classList.remove('hidden');
    } else if (m.type === 'hide') {
      bar.classList.add('hidden');
    } else if (m.type === 'tick') {
      const p = Math.max(0, Math.min(1, Number(m.pos) || 0.5));
      // The dot's `left` is a percentage. CSS transitions do the smooth slide.
      dot.style.left = (p * 100) + '%';
    }
  });
})();
