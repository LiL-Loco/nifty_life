/**
 * Phase 0 spike — Discord voice capture.
 *
 * This file exists to answer three questions, and nothing else. It is not the
 * feature; it is the evidence that the feature is buildable. Every line here is
 * disposable once Phase 1 exists.
 *
 *   1. Does the voice connection reach Ready with DAVE enabled? Discord made DAVE
 *      mandatory on every voice channel in March 2026, and @discordjs/voice 0.19.0
 *      could not receive audio on a DAVE channel at all — reconnect loops, no
 *      `speaking` events, `DecryptionFailed`. 0.19.2 + @snazzah/davey is the fix.
 *   2. Do `receiver.speaking` events fire?
 *   3. Does audio actually arrive, per user, at a plausible bitrate?
 *
 * A negative answer to 1 or 2 is the finding that matters. The fallback is
 * py-cord, which reportedly handles DAVE correctly — but that is a second bot
 * process in another language, so it gets decided on evidence, not in advance.
 *
 * Run:
 *   npm run spike -- <voiceChannelId> [maxSeconds]
 *
 * Writes one WAV per captured segment to `bot/.spike-out/`. Those files are
 * deliberately fed to `cache/voice-spike/vad_check.py` afterwards: capturing
 * audio and transcribing it are two separate claims, and proving one does not
 * prove the other.
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import {
  EndBehaviorType,
  VoiceConnectionStatus,
  generateDependencyReport,
  joinVoiceChannel,
  type VoiceConnection,
} from '@discordjs/voice';
import { Client, GatewayIntentBits, Partials } from 'discord.js';
import prism from 'prism-media';

import { loadConfig } from '../config.js';

/** Discord hands us 48 kHz, 16-bit, stereo. */
const SAMPLE_RATE = 48000;
const CHANNELS = 2;
const BITS_PER_SAMPLE = 16;

/** One speaker going quiet for this long closes their current segment. */
const SILENCE_TO_CLOSE_MS = 1500;

const OUT_DIR = join(process.cwd(), '.spike-out');

interface Speaker {
  userId: string;
  username: string;
  segments: number;
  bytes: number;
  files: string[];
}

const speakers = new Map<string, Speaker>();
let connection: VoiceConnection | null = null;
let finished = false;

/** Wrap raw PCM in a 44-byte canonical WAV header. */
function wavHeader(dataBytes: number): Buffer {
  const header = Buffer.alloc(44);
  const byteRate = (SAMPLE_RATE * CHANNELS * BITS_PER_SAMPLE) / 8;

  header.write('RIFF', 0, 'ascii');
  header.writeUInt32LE(36 + dataBytes, 4);
  header.write('WAVE', 8, 'ascii');
  header.write('fmt ', 12, 'ascii');
  header.writeUInt32LE(16, 16); // PCM header size
  header.writeUInt16LE(1, 20); // format 1 = PCM
  header.writeUInt16LE(CHANNELS, 22);
  header.writeUInt32LE(SAMPLE_RATE, 24);
  header.writeUInt32LE(byteRate, 28);
  header.writeUInt16LE((CHANNELS * BITS_PER_SAMPLE) / 8, 32); // block align
  header.writeUInt16LE(BITS_PER_SAMPLE, 34);
  header.write('data', 36, 'ascii');
  header.writeUInt32LE(dataBytes, 40);
  return header;
}

function flushSegment(userId: string, username: string, pcm: Buffer): void {
  const speaker = speakers.get(userId);
  if (!speaker || pcm.length === 0) return;

  speaker.segments += 1;
  speaker.bytes += pcm.length;

  const seconds = pcm.length / (SAMPLE_RATE * CHANNELS * (BITS_PER_SAMPLE / 8));
  const file = `${userId}-${speaker.segments}-${Date.now()}.wav`;
  writeFileSync(join(OUT_DIR, file), Buffer.concat([wavHeader(pcm.length), pcm]));
  speaker.files.push(file);

  console.log(
    `[segment] ${username} #${speaker.segments} ${seconds.toFixed(1)}s -> ${file}`,
  );
}

function attachReceiver(conn: VoiceConnection): void {
  // In 0.19.x the `speaking` event moved off VoiceReceiver and onto SpeakingMap.
  // `receiver.on('speaking', ...)` is what every tutorial online still shows, and
  // TypeScript rejects it because VoiceReceiver is no longer an EventEmitter.
  // You still subscribe through the receiver; `receiver.speaking` is the emitter
  // that says who started talking.
  conn.receiver.speaking.on('start', (userId: string) => {
    if (!speakers.has(userId)) {
      // The member may not be cached; the id alone is enough to label the file.
      speakers.set(userId, {
        userId,
        username: `<${userId}>`,
        segments: 0,
        bytes: 0,
        files: [],
      });
      console.log(`[speaking] first audio from ${userId}`);
    }

    const speaker = speakers.get(userId)!;

    const opusStream = conn.receiver.subscribe(userId, {
      end: {
        behavior: EndBehaviorType.AfterSilence,
        duration: SILENCE_TO_CLOSE_MS,
      },
    });

    const decoder = new prism.opus.Decoder({
      frameSize: 960,
      channels: CHANNELS,
      rate: SAMPLE_RATE,
    });

    const chunks: Buffer[] = [];
    opusStream
      .pipe(decoder)
      .on('data', (chunk: Buffer) => chunks.push(chunk))
      .on('end', () => flushSegment(userId, speaker.username, Buffer.concat(chunks)))
      .on('error', (error: Error) => {
        console.error(`[decode error] ${speaker.username}: ${error.message}`);
      });

    opusStream.on('error', (error: Error) => {
      console.error(`[opus stream error] ${speaker.username}: ${error.message}`);
    });
  });

  conn.receiver.speaking.on('end', (userId: string) => {
    const speaker = speakers.get(userId);
    if (speaker) console.log(`[speaking] ${speaker.username} stopped`);
  });
}

function stop(reason: string): void {
  if (finished) return;
  finished = true;

  console.log(`\n[stop] ${reason}`);

  if (connection) {
    try {
      connection.destroy();
    } catch (error) {
      console.error('[stop] destroy failed:', error);
    }
  }

  // Give the decoder streams a tick to flush their trailing buffers.
  setTimeout(() => {
    if (speakers.size === 0) {
      console.log('[result] NO AUDIO CAPTURED — this is the failure mode to report');
      process.exit(1);
    }

    console.log('[result] captured audio:');
    let totalBytes = 0;
    for (const speaker of speakers.values()) {
      const seconds = speaker.bytes / (SAMPLE_RATE * CHANNELS * (BITS_PER_SAMPLE / 8));
      totalBytes += speaker.bytes;
      console.log(
        `  ${speaker.username}: ${speaker.segments} segment(s), ${seconds.toFixed(1)}s`,
      );
      for (const file of speaker.files) console.log(`    ${file}`);
    }
    console.log(`  total ${(totalBytes / 1024 / 1024).toFixed(2)} MB in ${OUT_DIR}`);
    console.log('\nNext: feed those WAVs to cache/voice-spike/vad_check.py');
    process.exit(0);
  }, 1000);
}

async function main(): Promise<void> {
  const [channelId, maxSecondsRaw] = process.argv.slice(2);
  if (!channelId) {
    console.error('usage: npm run spike -- <voiceChannelId> [maxSeconds]');
    process.exit(1);
  }
  const maxSeconds = Number(maxSecondsRaw ?? 120);

  const config = loadConfig();

  console.log(generateDependencyReport());

  const client = new Client({
    // GuildVoiceStates is NOT privileged, so there is nothing to toggle in the
    // Developer Portal for it. GuildMembers is already required by the mirror.
    intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMembers, GatewayIntentBits.GuildVoiceStates],
    partials: [Partials.GuildMember],
  });

  client.once('ready', async () => {
    const guild = client.guilds.cache.get(config.guildId);
    if (!guild) {
      console.error(`[fatal] not in guild ${config.guildId}`);
      process.exit(1);
    }

    const channel = await guild.channels.fetch(channelId).catch(() => null);
    if (!channel || !('isVoiceBased' in channel) || !channel.isVoiceBased()) {
      console.error(`[fatal] ${channelId} is not a voice channel`);
      process.exit(1);
    }

    mkdirSync(OUT_DIR, { recursive: true });

    console.log(`[spike] joining ${channel.name} (${channelId}) as ${client.user?.tag}`);

    connection = joinVoiceChannel({
      channelId,
      guildId: guild.id,
      adapterCreator: guild.voiceAdapterCreator,
      // The bot must be able to HEAR the channel. Without this it joins deaf and
      // receives nothing at all, which looks exactly like a DAVE failure.
      selfDeaf: false,
      daveEncryption: true,
    });

    connection.on(VoiceConnectionStatus.Ready, () => {
      console.log('[spike] READY — DAVE handshake succeeded');
      console.log('[spike] speak now, then remove the bot from the channel');
      console.log(`[spike] hard stop after ${maxSeconds}s`);
      setTimeout(() => stop(`max duration of ${maxSeconds}s reached`), maxSeconds * 1000);
    });

    connection.on(VoiceConnectionStatus.Signalling, () => console.log('[spike] signalling'));
    connection.on(VoiceConnectionStatus.Connecting, () => console.log('[spike] connecting'));
    // (oldState, newState) — the reason string lives on the new state, which is
    // why the naive one-argument form does not type-check.
    connection.on(VoiceConnectionStatus.Disconnected, (_oldState, newState) =>
      console.error('[spike] disconnected:', newState.reason ?? 'unknown'),
    );
    connection.on(VoiceConnectionStatus.Destroyed, () => stop('voice connection destroyed'));

    connection.on('error', (error: Error) => console.error('[spike] error:', error.message));

    attachReceiver(connection);
  });

  // The bot being removed from the channel is the stop signal this whole
  // feature is built around, so the spike has to exercise exactly that path.
  client.on('voiceStateUpdate', (oldState, newState) => {
    if (!connection) return;
    if (newState.id !== client.user?.id) return;
    if (oldState.sessionId && !newState.sessionId) {
      stop('bot was disconnected from the channel');
    }
  });

  process.on('SIGINT', () => stop('SIGINT'));
  process.on('SIGTERM', () => stop('SIGTERM'));

  await client.login(config.token);
}

main().catch((error) => {
  console.error('[fatal]', error);
  process.exit(1);
});