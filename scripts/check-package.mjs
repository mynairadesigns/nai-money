#!/usr/bin/env node
/**
 * Pre-zip safety check for the buyer distribution.
 *
 * The zip is built with `git archive HEAD`, so it contains exactly the TRACKED
 * files. Anything real that reaches a tracked file ships to every buyer — their
 * builds would point at the seller's Firebase project, and any key would be
 * public. This is enforced rather than remembered because it has already gone
 * wrong three times here: a populated `.env.example`, `apps/mobile/firebase.json`
 * carrying the project and app ids, and `.firebaserc` swept in by `git add -A`.
 *
 * The stakes went UP when hosting moved to Vercel. A Google runtime supplies
 * credentials through the metadata server and no key file ever exists; Vercel
 * has no such thing, so `FIREBASE_SERVICE_ACCOUNT_JSON` now holds a key with
 * full administrative access that bypasses every security rule. This script is
 * what stops that key reaching the distribution.
 *
 * Two kinds of check:
 *
 *   1. GENERIC — patterns that are secret-shaped no matter whose they are
 *      (Firebase API keys, app ids, RevenueCat/OpenAI keys, private keys).
 *      These work for a buyer running this script on their own fork.
 *
 *   2. SPECIFIC — every value found in the machine's own gitignored config
 *      must not appear in any tracked file. Derived at runtime, so this script
 *      contains no secrets of its own.
 *
 * Usage:
 *   pnpm check:package     # verify only
 *   pnpm package           # verify, then build the zip
 */
import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');

const RED = '[31m';
const YELLOW = '[33m';
const GREEN = '[32m';
const DIM = '[2m';
const OFF = '[0m';

/** Secret-shaped patterns. Deliberately narrow — a false positive blocks a release. */
const GENERIC = [
  { name: 'Firebase Web API key', re: /AIzaSy[A-Za-z0-9_\-]{30,}/g },
  { name: 'Firebase app id', re: /\b1:\d{8,}:(?:web|android|ios):[a-f0-9]{6,}/gi },
  { name: 'RevenueCat SDK key', re: /\b(?:appl|goog)_[A-Za-z0-9]{15,}/g },
  { name: 'RevenueCat secret key', re: /\bsk_[A-Za-z0-9]{20,}/g },
  { name: 'OpenAI key', re: /\bsk-[A-Za-z0-9_\-]{20,}/g },
  // The private-key blob is the unambiguous marker. A service-account JSON is
  // useless without it, and it survives JSON escaping (\n), so this catches the
  // key whether it is a .json file or crammed into one env-var line.
  //
  // There is deliberately NO rule for `"type": "service_account"` alone: that
  // string appears in documentation showing the expected SHAPE — including in
  // .env.example — and flagging it trains people to ignore this check.
  { name: 'Google service-account key', re: /-----BEGIN [A-Z ]*PRIVATE KEY-----/g },
];

/** Files whose values must never appear in tracked files. All gitignored. */
const SOURCES_OF_TRUTH = ['apps/admin/.env.local', 'apps/admin/.env'];

/**
 * Values too short or too common to search for safely. Matching on "true" or a
 * port number would flag every file in the repo.
 */
const MIN_SECRET_LENGTH = 12;
const IGNORED_VALUES = new Set(['true', 'false', 'localhost', 'your-project']);

/**
 * Distinguishes a template placeholder from a real credential.
 *
 * The `.example` files deliberately carry realistically-SHAPED values so the
 * expected format is obvious — `1:000000000000:android:0000…` matches the app-id
 * pattern exactly. Flagging those would make this check cry wolf, and a check
 * that cries wolf gets bypassed, which defeats the entire point.
 *
 * Note it does NOT trust the filename: a `.example` file with a real value in it
 * is precisely the leak this repo has already had once, so the test is on the
 * value itself. A placeholder is one where every long alphanumeric run is a
 * single repeated character (000000, aaaaaa), or which says so in words.
 */
function looksLikePlaceholder(match) {
  if (/x{6,}|example|changeme|your-|placeholder/i.test(match)) return true;

  // Only the identifier-shaped runs count. A match like
  // `1:000000000000:android:0000…` also contains the literal word "android",
  // which is obviously not a repeated character and would otherwise veto the
  // whole test. Restricting to hex/digit runs leaves just the parts that carry
  // a value.
  const runs = (match.match(/[A-Za-z0-9]{6,}/g) ?? []).filter((run) =>
    /^[0-9a-f]+$/i.test(run),
  );

  // Nothing identifier-shaped to judge (an API key is not hex) — treat it as
  // real. Erring toward a false alarm is right here; erring the other way ships
  // a credential.
  if (runs.length === 0) return false;

  return runs.every((run) => new Set(run.toLowerCase()).size === 1);
}

/**
 * Everything that could end up in the zip.
 *
 * NOT just `git ls-files`. That lists only what is already tracked, so a file
 * created and then `git add -A`'d passes this check while untracked and ships
 * on the very next commit — which is exactly how `.firebaserc` (containing the
 * project id) slipped through once. `--cached --others --exclude-standard`
 * adds staged and untracked-but-not-ignored files, so the check sees a leak
 * BEFORE it is committed rather than after.
 */
function tracked() {
  const out = execFileSync(
    'git',
    ['ls-files', '--cached', '--others', '--exclude-standard'],
    { cwd: repoRoot, encoding: 'utf8' },
  );
  return [...new Set(out.split('\n').filter(Boolean))];
}

/** Pulls candidate secret values out of a dotenv file. */
function extractValues(path) {
  const out = new Set();
  if (!existsSync(path)) return out;
  const text = readFileSync(path, 'utf8');

  for (const line of text.split('\n')) {
    if (/^\s*#/.test(line)) continue;

    const env = /^\s*[A-Z0-9_]+\s*=\s*(.+?)\s*$/.exec(line);
    if (!env) continue;

    const value = env[1].replace(/^['"]|['"]$/g, '').trim();
    if (value.length >= MIN_SECRET_LENGTH && !IGNORED_VALUES.has(value)) {
      out.add(value);
    }
  }
  return out;
}

const failures = [];

// --- Check 1: vercel.json must not declare environment variables ------------
//
// `vercel.json` supports `env` and `build.env` blocks, so it is a real place a
// credential could be committed — and it ships to buyers. Everything belongs in
// the Vercel dashboard instead.
//
// Parsed as JSON, not scanned line-by-line: the earlier version looked for YAML
// `value:` lines left over from the apphosting config it replaced, which cannot
// occur in a JSON file, so it silently matched nothing.
const vercelJson = join(repoRoot, 'apps/admin/vercel.json');
if (existsSync(vercelJson)) {
  try {
    const cfg = JSON.parse(readFileSync(vercelJson, 'utf8'));
    for (const [key, block] of [
      ['env', cfg.env],
      ['build.env', cfg.build?.env],
    ]) {
      const names = block && typeof block === 'object' ? Object.keys(block) : [];
      if (names.length > 0) {
        failures.push({
          file: 'apps/admin/vercel.json',
          what: `declares ${key} (${names.join(', ')})`,
          why: 'This file ships to buyers. Environment values belong in the Vercel dashboard (Settings → Environment Variables), never in a committed file.',
        });
      }
    }
  } catch (e) {
    // Malformed JSON would break the Vercel build, so it is worth failing on.
    failures.push({
      file: 'apps/admin/vercel.json',
      what: 'is not valid JSON',
      why: e instanceof Error ? e.message : String(e),
    });
  }
}

// --- Check 2: no gitignored env/secret file is tracked ----------------------
const trackedFiles = tracked();
for (const f of trackedFiles) {
  const base = basename(f);
  if (/^\.env($|\.)/.test(base) && base !== '.env.example') {
    failures.push({
      file: f,
      what: 'env file is tracked',
      why: 'Only .env.example may be committed.',
    });
  }
}

// --- Check 3: generic secret-shaped strings in tracked files ---------------
// --- Check 4: this machine's own real values in tracked files --------------
const mine = new Set();
for (const s of SOURCES_OF_TRUTH) {
  for (const v of extractValues(join(repoRoot, s))) mine.add(v);
}

const SKIP = /^(pnpm-lock\.yaml|package-lock\.yaml|.*\.(png|jpg|jpeg|webp|gif|ico|ttf|otf|woff2?|zip|jar|keystore))$/i;

for (const f of trackedFiles) {
  if (SKIP.test(basename(f))) continue;
  // The check script necessarily contains the patterns it searches for.
  if (f === 'scripts/check-package.mjs') continue;

  const abs = join(repoRoot, f);
  if (!existsSync(abs)) continue;

  let text;
  try {
    text = readFileSync(abs, 'utf8');
  } catch {
    continue; // binary or unreadable
  }

  for (const { name, re } of GENERIC) {
    re.lastIndex = 0;
    let hit;
    while ((hit = re.exec(text)) !== null) {
      if (looksLikePlaceholder(hit[0])) continue;
      failures.push({
        file: f,
        line: text.slice(0, hit.index).split('\n').length,
        what: `${name} — ${hit[0].slice(0, 12)}…`,
        why: 'Secret-shaped string in a tracked file. It would ship in the buyer zip.',
      });
      break; // one report per pattern per file is enough to block the build
    }
  }

  for (const value of mine) {
    const idx = text.indexOf(value);
    if (idx !== -1) {
      failures.push({
        file: f,
        line: text.slice(0, idx).split('\n').length,
        what: `your own config value "${value.slice(0, 16)}…"`,
        why: 'Found in one of your gitignored files, so it is real. Buyers must not receive it.',
      });
    }
  }
}

// --- Report ----------------------------------------------------------------
console.log('');
if (failures.length === 0) {
  console.log(`  ${GREEN}✓${OFF} Package check passed — ${trackedFiles.length} tracked files, nothing leaking.`);
  if (mine.size === 0) {
    console.log(
      `  ${YELLOW}!${OFF} No gitignored config found, so only the generic patterns ran.\n` +
        `    ${DIM}Run this on the machine that holds .env.local for the full check.${OFF}`,
    );
  }
  console.log('');
  process.exit(0);
}

console.log(`  ${RED}✗ Package check FAILED — ${failures.length} problem(s). The zip was not built.${OFF}\n`);
for (const f of failures) {
  console.log(`  ${RED}${f.file}${f.line ? `:${f.line}` : ''}${OFF}`);
  console.log(`    ${f.what}`);
  console.log(`    ${DIM}${f.why}${OFF}\n`);
}
process.exit(1);
