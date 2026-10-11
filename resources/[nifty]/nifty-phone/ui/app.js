// Nifty Life 2.0 — phone UI.
//
// Presentation only. Whether a message may be sent, whether the addressee is a real
// character, and whether a report is legitimate are all answered in
// server/phone.lua. `phoneSend` hands over a number the player typed; the server
// resolves it to a character itself, and nothing here can choose the recipient.

const { nui, $, toast } = Nifty;

const phone = {
  account: null,
  inbox: [],
  unread: 0,
  activeApp: 'messages',
};

function renderPhoneBadge(unread) {
  phone.unread = unread;

  const badge = $('phoneBadgeTop');
  if (!badge) return;

  badge.textContent = String(unread);
  badge.classList.toggle('hidden', unread <= 0);
}

function messageRow(message) {
  const row = document.createElement('div');
  row.className = 'phone__message';

  if (!message.read_at) row.classList.add('phone__message--unread');

  const meta = document.createElement('div');
  meta.className = 'phone__meta';

  const from = document.createElement('span');
  // textContent, never innerHTML: a sender name is player input.
  from.className = 'phone__from';
  from.textContent = message.from_number || '—';

  const time = document.createElement('span');
  time.className = 'phone__time';
  time.textContent = message.created_at || '';

  meta.appendChild(from);
  meta.appendChild(time);

  const body = document.createElement('p');
  body.className = 'phone__body';
  body.textContent = message.body || '';

  const actions = document.createElement('div');
  actions.className = 'phone__actions';

  const reply = document.createElement('button');
  reply.type = 'button';
  reply.className = 'btn btn--ghost btn--small';
  reply.textContent = 'Antworten';
  reply.addEventListener('click', () => {
    const to = $('phoneTo');
    if (to) to.value = message.from_number || '';
    switchPhoneApp('compose');
  });

  const reason = document.createElement('select');
  reason.className = 'phone__reason';
  [
    ['spam', 'Spam'],
    ['harassment', 'Belästigung'],
    ['impersonation', 'Identitätsmissbrauch'],
    ['other', 'Sonstiges'],
  ].forEach(([value, label]) => {
    const option = document.createElement('option');
    option.value = value;
    option.textContent = label;
    reason.appendChild(option);
  });

  const report = document.createElement('button');
  report.type = 'button';
  report.className = 'btn btn--ghost btn--small';
  report.textContent = 'Melden';
  report.addEventListener('click', () => {
    nui('phoneReport', { id: message.id, reason: reason.value });
  });

  actions.appendChild(reply);
  actions.appendChild(reason);
  actions.appendChild(report);

  row.appendChild(meta);
  row.appendChild(body);
  row.appendChild(actions);

  return row;
}

function switchPhoneApp(name) {
  phone.activeApp = name;

  document.querySelectorAll('.phone__tab').forEach((tab) => {
    tab.classList.toggle('is-active', tab.dataset.app === name);
  });

  $('appMessages')?.classList.toggle('is-active', name === 'messages');
  $('appCompose')?.classList.toggle('is-active', name === 'compose');
}

function renderPhone(data) {
  phone.account = data.account || null;
  phone.inbox = Array.isArray(data.inbox) ? data.inbox : [];
  renderPhoneBadge(Number(data.unread) || 0);

  const shell = $('phone');
  if (!shell) return;

  shell.classList.toggle('hidden', data.open !== true);
  if (data.open !== true) return;

  const number = $('phoneNumber');
  if (number) {
    // The server's number, always. The UI has no way to set it.
    number.textContent = phone.account && phone.account.number
      ? phone.account.number
      : '—';
  }

  const list = $('phoneList');
  if (list) {
    // Rebuilt wholesale, so a deleted message disappears instead of lingering.
    list.innerHTML = '';

    if (phone.inbox.length === 0) {
      const empty = document.createElement('p');
      empty.className = 'phone__empty';
      empty.textContent = 'Keine Nachrichten.';
      list.appendChild(empty);
    } else {
      phone.inbox.forEach((message) => list.appendChild(messageRow(message)));
    }
  }
}

window.addEventListener('message', (event) => {
  const { action, data } = event.data || {};
  if (!action) return;

  if (action === 'phone') {
    renderPhone(data);
    return;
  }

  if (action === 'phoneBadge') {
    renderPhoneBadge(Number(data.unread) || 0);
    return;
  }

  if (action === 'result') {
    toast(data.ok, data.message);
  }
});

(function wirePhone() {
  document.querySelectorAll('.phone__tab').forEach((tab) => {
    tab.addEventListener('click', () => switchPhoneApp(tab.dataset.app));
  });

  // The homebar doubles as the close target, which is why there is no X button.
  const homebar = document.querySelector('.phone__homebar');
  if (homebar) homebar.addEventListener('click', () => nui('phoneClose', {}));

  const send = $('phoneSend');
  if (send) {
    send.addEventListener('click', () => {
      const number = ($('phoneTo')?.value || '').trim();
      const body = ($('phoneBody')?.value || '').trim();

      // Stopped here so the player does not wait for a round trip to be told
      // nothing. This is convenience, NOT a rule — the server performs the same
      // check and is the only thing that enforces it.
      if (number === '' || body === '') {
        toast(false, 'Nummer und Nachricht werden beide gebraucht.');
        return;
      }

      nui('phoneSend', { number, body });

      const to = $('phoneTo');
      const text = $('phoneBody');
      if (to) to.value = '';
      if (text) text.value = '';

      switchPhoneApp('messages');
    });
  }
})();