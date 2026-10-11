/**
 * One-off: list the tunables in `settings` so a new feature can reuse an
 * existing key instead of hardcoding a number (ADR-0009).
 *
 * Written to a FILE rather than passed with `node -e` because PowerShell treats
 * a backtick as an escape character, and `` `key` `` is a MySQL identifier quote.
 * That silently corrupted the query string twice before this was written down.
 *
 * Run: node tools/list-settings.js
 */
const fs = require('fs');
const path = require('path');

const envPath = path.join(__dirname, '..', '.env');
for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
  const at = line.indexOf('=');
  if (at > 0) process.env[line.slice(0, at).trim()] = line.slice(at + 1).trim();
}

const mysql = require('mysql2/promise');

(async () => {
  const conn = await mysql.createConnection({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
  });

  const [rows] = await conn.query('SELECT `key`, value, value_type FROM settings ORDER BY `key`');
  console.log(`settings (${rows.length}):`);
  for (const row of rows) console.log(`  ${row.key} = ${row.value}  (${row.value_type})`);

  await conn.end();
})().catch((error) => {
  console.error(error.message);
  process.exit(1);
});