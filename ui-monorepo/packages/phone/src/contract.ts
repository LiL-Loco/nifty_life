import { createBridge, type Result } from '@nifty/bridge';

/**
 * The nifty-phone Lua <-> NUI contract, typed.
 *
 * THIS FILE IS THE OTHER HALF OF `shared/contract.lua`, and the two are meant to
 * be read together. Every action name below appears there, in the same spelling,
 * for the same reason: `SendNUIMessage` is a shared channel and every resource
 * with a `ui_page` sees every message, so a bare `open` would unhide the creator,
 * the shop and the inventory at once.
 *
 * If the two files drift apart the build fails, which is the point. A phone panel
 * that answers nothing is indistinguishable from one that is merely slow.
 */

/* ------------------------------------------------------------------ shapes */

/** `phone_accounts` + the character's own name. */
export interface PhoneAccount {
  number: string;
  /** Staff suspension. NOT whether the character is holding a handset. */
  active: boolean;
  firstName: string;
  lastName: string;
}

/** One row of `phone_contacts`, joined with the name that number belongs to. */
export interface PhoneContact {
  contact_id: string;
  /** The name THIS owner gave them. null means "never renamed". */
  alias: string | null;
  number: string;
  is_active: number;
  first_name: string;
  last_name: string;
}

/** One conversation. `unread` is derived, never a stored counter. */
export interface PhoneThread {
  number: string;
  first_name: string;
  last_name: string;
  alias: string | null;
  last_body: string;
  last_at: string;
  last_sender: string;
  unread: number | null;
}

/** One row of `phone_messages`. */
export interface PhoneMessage {
  id: string;
  sender_id: string;
  recipient_id: string;
  body: string;
  sent_at: string;
  read_at: string | null;
}

/** One row of `phone_calls`, as the call log draws it. */
export interface PhoneCallLogEntry {
  id: string;
  caller_id: string;
  callee_id: string;
  started_at: string;
  answered_at: string | null;
  end_reason: CallEndReason | null;
  number: string;
  first_name: string;
  last_name: string;
  /**
   * Computed server-side as `caller_id = <the caller>`. The panel is NOT told its
   * own character id, so "did I place this call" is a question only the server
   * can answer — and a panel that guesses renders "Verpasst" for a call somebody
   * else missed, which is the one thing a call log must never get backwards.
   */
  outbound: number;
}

/**
 * The four call states. A union rather than two booleans on purpose: a view model
 * that has to decide between `ringing` and `connected` is a view model that will
 * eventually draw both.
 */
export type CallState = 'idle' | 'outgoing' | 'incoming' | 'active';

export type CallEndReason =
  | 'answered'
  | 'declined'
  | 'missed'
  | 'busy'
  | 'cancelled'
  | 'unavailable';

/** The live call, in the shape the panel draws. `null` means idle. */
export interface LiveCall {
  id: string;
  state: CallState;
  outbound: boolean;
  with: { number: string; name: string };
  startedAt: string;
  /**
   * False rather than absent: the panel can then say "kein Ton" honestly instead
   * of hiding the call row it should be showing. It is false today because
   * ADR-0020's Teamspeak transport is not configured.
   */
  hasVoice: boolean;
}

/** The incoming-call push, which arrives before the panel is open. */
export interface IncomingCall {
  id: string;
  from?: string;
  name?: string;
  /** Present on updates after the first: `active` when answered, `idle` when over. */
  state?: CallState;
  peer?: string;
  reason?: CallEndReason;
}

/** What `phone:open` carries. One message, so the panel renders once. */
export interface PhoneOpenPayload {
  account: PhoneAccount;
  contacts: PhoneContact[];
  threads: PhoneThread[];
  call: LiveCall | null;
  callLog: PhoneCallLogEntry[];
  unread: number;
  limits: { MESSAGE_BODY: number; ALIAS: number; THREAD_PAGE: number };
}

/** Partial `phone:threads` pushes — only one of these is present at a time. */
export interface PhoneThreadsPayload {
  sent?: PhoneMessage;
  read?: string;
  cleared?: string;
  bump?: { from: string; name: string; preview: string };
}

/**
 * What the panel is allowed to receive.
 *
 * `render` is not in the list because this panel has no HUD: everything is
 * pushed by a named action, and the panel draws nothing at all until `phone:open`
 * arrives. A panel with a permanent surface would need one, and it does not have
 * one — the phone is a thing you hold, not a thing that sits on the screen.
 */
/** One conversation's messages, fetched when the thread view opens. */
export interface PhoneThreadPayload {
  number: string;
  messages: PhoneMessage[];
}

// A `type` and not an `interface`, and the reason is not style. ActionMap is
// `Record<string, (body: any) => void>`, and TypeScript gives an object-literal
// TYPE ALIAS an implicit index signature while giving an INTERFACE none. So the
// same shape compiles as one and is rejected as the other, with an error that
// says "index signature is missing" and points at a constraint rather than at
// the thing that actually differs.
type PhoneActions = {
  'phone:open': PhoneOpenPayload;
  'phone:close': null;
  'phone:call': { call: LiveCall | IncomingCall | null };
  'phone:threads': PhoneThreadsPayload;
  'phone:thread': PhoneThreadPayload;
  'phone:contacts': { contacts: PhoneContact[] };
  'phone:error': { message: string };
  'phone:toast': { message: string };
};

const bridge = createBridge<PhoneActions>({
  received: [
    'phone:open',
    'phone:close',
    'phone:call',
    'phone:threads',
    'phone:thread',
    'phone:contacts',
    'phone:error',
    'phone:toast',
  ],
});

/* --------------------------------------------------------------- callbacks */

/**
 * Every `RegisterNUICallback` in nifty-phone, with the body it reads.
 *
 * The names are prefixed and the panel therefore cannot accidentally invoke
 * `closePanel`, which is registered by nifty-clothing, nifty-inventory AND
 * nifty-world — and whichever answers first wins. That collision is in the tree.
 */
export interface PhoneCallbacks {
  phoneClose: Record<string, never>;
  phoneGetState: Record<string, never>;
  phoneSendMessage: { to: string; body: string };
  phoneOpenThread: { number: string; limit?: number };
  phoneMarkRead: { number: string };
  phoneClearThread: { number: string };
  phoneSaveContact: { number: string; alias?: string };
  phoneDeleteContact: { number: string };
  phoneCallStart: { number: string };
  phoneCallAnswer: Record<string, never>;
  phoneCallDecline: Record<string, never>;
  phoneCallEnd: Record<string, never>;
}

/** Fire a Lua callback. Returns a Result, never throws. */
export function send<K extends keyof PhoneCallbacks>(
  name: K,
  body: PhoneCallbacks[K],
): Promise<Result<unknown>> {
  return bridge.call(name, body);
}

/* ------------------------------------------------------------ subscriptions */

export function onOpen(handler: (data: PhoneOpenPayload) => void): () => void {
  return bridge.on('phone:open', handler);
}

export function onClose(handler: () => void): () => void {
  return bridge.on('phone:close', handler);
}

export function onCall(handler: (data: { call: LiveCall | IncomingCall | null }) => void): () => void {
  return bridge.on('phone:call', handler);
}

export function onThreads(handler: (data: PhoneThreadsPayload) => void): () => void {
  return bridge.on('phone:threads', handler);
}

export function onThread(handler: (data: PhoneThreadPayload) => void): () => void {
  return bridge.on('phone:thread', handler);
}

export function onContacts(handler: (data: { contacts: PhoneContact[] }) => void): () => void {
  return bridge.on('phone:contacts', handler);
}

export function onError(handler: (data: { message: string }) => void): () => void {
  return bridge.on('phone:error', handler);
}

export function onToast(handler: (data: { message: string }) => void): () => void {
  return bridge.on('phone:toast', handler);
}

/* ---------------------------------------------------------------- defaults */

/** What the panel renders before `phone:open` has ever arrived. */
export const EMPTY_ACCOUNT: PhoneAccount = {
  number: '',
  active: true,
  firstName: '',
  lastName: '',
};

/** The keypad layout, and the two letters under each digit. */
export const KEYPAD: { digit: string; letters: string }[] = [
  { digit: '1', letters: '' },
  { digit: '2', letters: 'ABC' },
  { digit: '3', letters: 'DEF' },
  { digit: '4', letters: 'GHI' },
  { digit: '5', letters: 'JKL' },
  { digit: '6', letters: 'MNO' },
  { digit: '7', letters: 'PQRS' },
  { digit: '8', letters: 'TUV' },
  { digit: '9', letters: 'WXYZ' },
  { digit: '*', letters: '' },
  { digit: '0', letters: '+' },
  { digit: '#', letters: '' },
];

/**
 * Render a number the way it is stored: `555-1234`.
 *
 * The server owns the format (ADR-0021 assigns `555-XXXX` and normalises every
 * input against it), so the panel formats for DISPLAY and never for storage. A
 * second spelling here would be a second truth about what a number is, and the
 * UNIQUE constraint on `phone_accounts.number` is a string comparison.
 */
export function formatNumber(digits: string): string {
  const body = digits.replace(/\D/g, '');
  if (body.length <= 3) return body;
  return `${body.slice(0, 3)}-${body.slice(3, 7)}`;
}

/** How a contact or thread is labelled. Alias first — it is the owner's choice. */
export function labelOf(row: {
  alias: string | null;
  first_name: string;
  last_name: string;
}): string {
  if (row.alias && row.alias.trim() !== '') return row.alias;
  const full = `${row.first_name} ${row.last_name}`.trim();
  return full === '' ? 'Unbekannt' : full;
}