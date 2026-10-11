/**
 * Outgoing mail — the confirmation link lives here.
 *
 * One deliberate decision: there is NO in-memory or file fallback. If SMTP is
 * not configured, sending throws, and the caller tells the person that no
 * confirmation could be sent. The alternative — queueing it somewhere and
 * hoping — produces the exact failure this project exists to avoid: an account
 * that looks fine and a confirmation that never arrives.
 *
 * nodemailer is MIT and free. It is the one place a dependency is justified
 * rather than merely convenient: hand-rolling STARTTLS, AUTH and certificate
 * handling is exactly the kind of crypto-adjacent code that should not be
 * written by hand. There is no paid tier and nothing here phones home.
 */
import 'server-only';

import nodemailer, { type Transporter } from 'nodemailer';

import { config } from './config';

export interface MailConfig {
  host: string;
  port: number;
  user: string;
  password: string;
  /** 'PLAIN' over STARTTLS is what every mainstream provider offers. */
  secure: boolean;
  from: string;
}

let transporter: Transporter | null = null;

/**
 * Read SMTP settings, or null when they are absent.
 *
 * Returning null rather than throwing lets a caller check once and decide what
 * to say, which is different from failing at import time and taking down every
 * page of the site because a mail server is down.
 */
export function mailConfig(): MailConfig | null {
  const host = process.env.SMTP_HOST?.trim();
  const user = process.env.SMTP_USER?.trim();
  const password = process.env.SMTP_PASSWORD?.trim();
  const from = process.env.MAIL_FROM?.trim();

  if (!host || !user || !password || !from) return null;

  return {
    host,
    port: Number(process.env.SMTP_PORT ?? 587),
    user,
    password,
    secure: (process.env.SMTP_SECURE ?? 'false').toLowerCase() === 'true',
    from,
  };
}

/** True when a confirmation could actually be delivered right now. */
export function mailConfigured(): boolean {
  return mailConfig() !== null;
}

function getTransport(): Transporter {
  const settings = mailConfig();
  if (!settings) {
    throw new Error(
      'SMTP is not configured. Set SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD ' +
        'and MAIL_FROM — see website/.env.example.',
    );
  }

  if (!transporter) {
    transporter = nodemailer.createTransport({
      host: settings.host,
      port: settings.port,
      secure: settings.secure,
      auth: { user: settings.user, pass: settings.password },
      // Generous, because the first connection to a new provider is often slow
      // and a timeout here looks like "registration is broken".
      connectionTimeout: 15000,
      greetingTimeout: 15000,
    });
  }

  return transporter;
}

export interface SendResult {
  ok: boolean;
  error?: string;
}

/**
 * Send one message.
 *
 * Returns a result rather than throwing: a failed confirmation mail is an
 * operational problem the person in front of the form needs an answer about, not
 * a stack trace. The caller decides what to tell them.
 */
export async function sendMail(options: {
  to: string;
  subject: string;
  text: string;
  html?: string;
}): Promise<SendResult> {
  const settings = mailConfig();
  if (!settings) {
    return { ok: false, error: 'E-Mail-Versand ist auf diesem Server nicht eingerichtet.' };
  }

  try {
    await getTransport().sendMail({
      from: settings.from,
      to: options.to,
      subject: options.subject,
      text: options.text,
      html: options.html,
    });
    return { ok: true };
  } catch (error) {
    // Logged, not surfaced. The SMTP host and the auth mode are useful in a
    // server log and useless — and mildly alarming — in a sign-up form.
    console.error('[mail] send failed:', error instanceof Error ? error.message : error);
    return { ok: false, error: 'Die Bestätigungs-E-Mail konnte nicht versendet werden.' };
  }
}

/**
 * The absolute URL of this site, used to build links in mails.
 *
 * A mail link that is relative is a broken link, so this cannot be guessed from
 * the request: the person confirming may well be on a different host than the
 * one that generated the token, and `x-forwarded-host` is attacker-controlled.
 */
export function publicUrl(path: string): string {
  const base = config.publicUrl.replace(/\/+$/, '');
  return `${base}${path.startsWith('/') ? path : `/${path}`}`;
}