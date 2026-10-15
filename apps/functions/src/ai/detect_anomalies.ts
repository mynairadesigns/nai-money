import * as admin from 'firebase-admin';
import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  buildDetectAnomaliesPrompt,
  type AnomalyCandidate,
  type AnomalyContext,
  type AnomalyTopTransaction,
} from '../prompts/detect_anomalies';
import { getProvider, selectProvider } from '../providers/select_provider';
import { checkAndIncrementQuota } from '../quota/check_quota';
import { enforceRateLimit } from '../quota/rate_limit';
import { REGION } from '../utils/region';

if (!admin.apps.length) admin.initializeApp();

const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');

const WINDOW_DAYS = 35; // 7 current + 28 trailing
const CURRENT_DAYS = 7;
const TRAILING_WEEKS = 4;
const ANOMALY_MULTIPLIER = 2; // PRD §7.7 — 2× threshold
const DAY_MS = 24 * 60 * 60 * 1000;

interface ValidatedAnomaly {
  transactionId?: string;
  categoryName: string;
  amount: number;
  currency: string;
  summary: string;
  severity: 'low' | 'medium' | 'high';
}

/**
 * Callable: anomaly detection — PRD §7.7.
 *
 * Per CLAUDE.md §7: auth → rate-limit → quota → RAG fetch → provider →
 * JSON validate. Server flags categories whose 7-day spend is ≥ 2× the
 * trailing 4-week average; the model classifies severity and writes
 * friendly summaries. If no candidates fire, we skip the LLM call.
 */
export const detectAnomalies = onCall(
  {
    region: REGION,
    memory: '512MiB',
    timeoutSeconds: 60,
    secrets: [OPENAI_API_KEY, GEMINI_API_KEY],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in required');
    }
    const uid = request.auth.uid;

    enforceRateLimit({
      uid,
      key: 'detectAnomalies',
      windowSeconds: 60,
      maxCalls: 3,
    });
    await checkAndIncrementQuota({ uid, field: 'anomalies' });

    const context = await buildAnomalyContext(uid);

    if (context.candidates.length === 0) {
      return { anomalies: [], summary: '' };
    }

    const providerName = await selectProvider({ featureDefault: 'gemini' });
    const model =
      providerName === 'openai' ? 'gpt-4o-mini' : 'gemini-2.5-flash-lite';
    const provider = getProvider(providerName, model);

    const { system, user } = buildDetectAnomaliesPrompt(context);

    let raw: unknown;
    try {
      raw = await provider.generateJson({ system, user });
    } catch (e) {
      console.error('detectAnomalies: provider error', e);
      throw new HttpsError('internal', 'AI provider error');
    }

    if (typeof raw !== 'object' || raw === null) {
      throw new HttpsError('internal', 'Malformed AI response');
    }
    const r = raw as Record<string, unknown>;
    const anomaliesRaw = r.anomalies;
    const summary = r.summary;
    if (!Array.isArray(anomaliesRaw) || typeof summary !== 'string') {
      throw new HttpsError('internal', 'AI response missing required fields');
    }

    const anomalies: ValidatedAnomaly[] = [];
    for (const a of anomaliesRaw) {
      if (typeof a !== 'object' || a === null) continue;
      const row = a as Record<string, unknown>;
      const categoryName = row.categoryName;
      const amount = row.amount;
      const currency = row.currency;
      const itemSummary = row.summary;
      const severity = row.severity;
      const transactionId = row.transactionId;
      if (
        typeof categoryName === 'string' &&
        typeof amount === 'number' &&
        typeof currency === 'string' &&
        typeof itemSummary === 'string' &&
        (severity === 'low' || severity === 'medium' || severity === 'high')
      ) {
        const out: ValidatedAnomaly = {
          categoryName,
          amount,
          currency,
          summary: itemSummary,
          severity,
        };
        if (typeof transactionId === 'string' && transactionId !== '') {
          out.transactionId = transactionId;
        }
        anomalies.push(out);
      }
    }

    return { anomalies, summary };
  },
);

async function buildAnomalyContext(uid: string): Promise<AnomalyContext> {
  const db = admin.firestore();
  const userRef = db.doc(`users/${uid}`);
  const now = new Date();
  const windowStart = new Date(now.getTime() - WINDOW_DAYS * DAY_MS);
  const currentStart = new Date(now.getTime() - CURRENT_DAYS * DAY_MS);

  const [userSnap, txSnap, categoriesSnap] = await Promise.all([
    userRef.get().catch((e) => {
      console.warn('detectAnomalies: user fetch failed', e);
      return null;
    }),
    userRef
      .collection('transactions')
      .where('date', '>=', admin.firestore.Timestamp.fromDate(windowStart))
      .get()
      .catch((e) => {
        console.warn('detectAnomalies: transactions fetch failed', e);
        return null;
      }),
    userRef
      .collection('categories')
      .get()
      .catch((e) => {
        console.warn('detectAnomalies: categories fetch failed', e);
        return null;
      }),
  ]);

  const currency = _str(userSnap?.data()?.defaultCurrency, 'NGN');

  const categoryNames = new Map<string, string>();
  categoriesSnap?.forEach((d) => {
    const name = _str(d.data().name, '');
    if (name) categoryNames.set(d.id, name);
  });

  // Bucket transactions per category into current-7d vs trailing-28d.
  interface PerCategory {
    currentSpend: number;
    trailingSpend: number;
    topTxs: AnomalyTopTransaction[];
  }
  const byCategory = new Map<string, PerCategory>();

  for (const doc of txSnap?.docs ?? []) {
    const t = doc.data();
    if (_str(t.type, '') !== 'expense') continue;
    const amount = _num(t.amount, 0);
    const dateIso = _str(t.date, '');
    const date = new Date(dateIso);
    if (!Number.isFinite(date.getTime())) continue;
    const catId = _str(t.categoryId, '');
    const catName = categoryNames.get(catId) ?? catId ?? '(uncategorized)';

    const isCurrent = date.getTime() >= currentStart.getTime();
    let bucket = byCategory.get(catName);
    if (!bucket) {
      bucket = { currentSpend: 0, trailingSpend: 0, topTxs: [] };
      byCategory.set(catName, bucket);
    }
    if (isCurrent) {
      bucket.currentSpend += amount;
      bucket.topTxs.push({
        transactionId: doc.id,
        amount,
        note: _str(t.note, ''),
        date: dateIso,
      });
    } else {
      bucket.trailingSpend += amount;
    }
  }

  const candidates: AnomalyCandidate[] = [];
  for (const [categoryName, b] of byCategory.entries()) {
    const avgWeekSpend = b.trailingSpend / TRAILING_WEEKS;
    if (avgWeekSpend <= 0) continue;
    const multiplier = b.currentSpend / avgWeekSpend;
    if (multiplier < ANOMALY_MULTIPLIER) continue;
    const topTransactions = b.topTxs
      .slice()
      .sort((x, y) => y.amount - x.amount)
      .slice(0, 5);
    candidates.push({
      categoryName,
      currentWeekSpend: b.currentSpend,
      averageWeekSpend: avgWeekSpend,
      multiplier,
      topTransactions,
    });
  }

  // Sort highest multiplier first so the most surprising spikes lead.
  candidates.sort((a, b) => b.multiplier - a.multiplier);

  return { currency, candidates: candidates.slice(0, 10) };
}

function _str(v: unknown, fallback: string): string {
  return typeof v === 'string' ? v : fallback;
}

function _num(v: unknown, fallback: number): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}
