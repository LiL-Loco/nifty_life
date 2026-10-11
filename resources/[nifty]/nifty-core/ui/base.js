// Nifty Life 2.0 — shared NUI runtime.
//
// Loaded by every system resource's page. It carries the three things that
// would otherwise be copy-pasted into ten files, and that MUST NOT drift apart:
// the callback transport, the toast, and the panel shell.
//
// It is a global `Nifty` object rather than a module system on purpose. These
// pages are plain CEF documents loaded over https://cfx-nui-<resource>/, with no
// bundler and no build step (ADR-0002). A module loader would be a framework,
// which is the one thing this project does not have.

const Nifty = (() => {
  /**
   * Call a NUI callback on the Lua side of THIS resource.
   *
   * `https://`, not `http://`. The page is served from
   * `https://cfx-nui-<resource>/html/index.html`, so an `http://` request to the
   * resource is MIXED CONTENT: CEF blocks it before it leaves the browser and the
   * Lua callback never runs.
   *
   * This was not a typo nobody noticed. It was `http://` in the single fetch helper
   * of the only NUI file the project had, so EVERY NUI callback in the resource was
   * blocked — creator submit, panels, phone. It surfaced only because `chat` was
   * started and its own mixed-content warning made somebody look at the scheme in
   * the first place. With the split there would have been ten copies of it.
   */
  async function nui(name, body) {
    const res = await fetch(`https://${GetParentResourceName()}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(body || {}),
    });
    return res.json();
  }

  const $ = (id) => document.getElementById(id);

  /**
   * A transient message, styled by outcome.
   *
   * `textContent`, never `innerHTML`: every string that reaches it came from a
   * player or the server on that player's behalf, and NUI runs on the machine
   * that runs the server.
   */
  function toast(ok, message, ms = 3200) {
    const el = $('toast');
    if (!el) return;

    el.textContent = message || '';
    el.classList.remove('hidden');
    el.classList.toggle('toast--error', ok === false);

    clearTimeout(el.dataset.timer);
    el.dataset.timer = String(setTimeout(() => el.classList.add('hidden'), ms));
  }

  return { nui, $, toast };
})();