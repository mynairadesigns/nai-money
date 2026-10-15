import * as admin from 'firebase-admin';
import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  buildCoachChatPrompt,
  type CoachContext,
  type CoachHistoryMsg,
} from '../prompts/coach_chat';
import { getProvider, selectProvider } from '../providers/select_provider';
import { checkAndIncrementQuota } from '../quota/check_quota';
import { enforceRateLimit } from '../quota/rate_limit';
import { REGION } from '../utils/region';
import { GEMINI_FAST } from '../providers/models';

if (!admin.apps.length) admin.initializeApp();

const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');

const RECENT_TX_WINDOW_DAYS = 30;
const HISTORY_LIMIT = 10;
const PREVIEW_MAX_CHARS = 120;

interface ChatInput {
  message: string;
  sessionId?: string;
}

/**
 * Callable: AI Finance Coach (RAG chat) — PRD §7.5.
 *
 * Per CLAUDE.md §7: auth → rate-limit → quota → RAG fetch → provider →
 * JSON validate → persist user+assistant messages → return.
 * Feature default provider is **Gemini Flash** (cheap chat);
 * Remote Config `ai_provider` can override globally.
 *
 * Conversation history (last 10 messages) is folded into the user prompt;
 * the provider abstraction only does single-shot JSON calls.
 *
 * Response shape:
 *   { sessionId, userMessageId, assistantMessageId, reply }
 */
export const aiCoachChat = onCall(
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
      key: 'aiCoachChat',
      windowSeconds: 60,
      maxCalls: 5,
    });
    const quota = await checkAndIncrementQuota({ uid, field: 'chat' });

    const input = _validateInput(request.data);
    const sessionId = input.sessionId ?? `${uid}_s_${Date.now()}`;
    const userMessageId = `${uid}_m_${Date.now()}_u`;

    const db = admin.firestore();
    const sessionRef = db.doc(`users/${uid}/aiChats/${sessionId}`);
    const messagesRef = sessionRef.collection('messages');
    const nowFv = admin.firestore.FieldValue.serverTimestamp();

    // 1. Persist the user message FIRST so it lives even if the AI call
    //    later throws — preserves the chat transcript for the client.
    try {
      await messagesRef.doc(userMessageId).set({
        id: userMessageId,
        userId: uid,
        sessionId,
        role: 'user',
        content: input.message,
        createdAt: nowFv,
        updatedAt: nowFv,
      });
    } catch (e) {
      console.error('aiCoachChat: failed to persist user message', e);
      throw new HttpsError('internal', 'Failed to save your message');
    }

    // 2. RAG: gather context + last-10 history in parallel.
    const [context, history] = await Promise.all([
      buildCoachContext(uid),
      _fetchHistory(messagesRef, userMessageId),
    ]);

    // 3. Provider call.
    const providerName = await selectProvider({ featureDefault: 'gemini' });
    const model =
      providerName === 'openai' ? 'gpt-4o-mini' : GEMINI_FAST;
    const provider = getProvider(providerName, model);

    const { system, user } = buildCoachChatPrompt({
      context,
      history,
      userMessage: input.message,
    });

    let raw: unknown;
    try {
      raw = await provider.generateJson({ system, user });
    } catch (e) {
      console.error('aiCoachChat: provider error', e);
      await quota.refund();
      throw new HttpsError('internal', 'AI provider error');
    }

    if (typeof raw !== 'object' || raw === null) {
      throw new HttpsError('internal', 'Malformed AI response');
    }
    const reply = (raw as Record<string, unknown>).reply;
    if (typeof reply !== 'string' || reply.trim() === '') {
      throw new HttpsError('internal', 'AI response missing reply');
    }

    // 4. Persist the assistant message + session metadata.
    const assistantMessageId = `${uid}_m_${Date.now()}_a`;
    try {
      const batch = db.batch();
      batch.set(messagesRef.doc(assistantMessageId), {
        id: assistantMessageId,
        userId: uid,
        sessionId,
        role: 'assistant',
        content: reply,
        createdAt: nowFv,
        updatedAt: nowFv,
      });
      batch.set(
        sessionRef,
        {
          id: sessionId,
          userId: uid,
          lastMessageAt: nowFv,
          lastMessagePreview: reply.substring(0, PREVIEW_MAX_CHARS),
          createdAt: nowFv, // merge: true → only persists on first turn
          updatedAt: nowFv,
        },
        { merge: true },
      );
      await batch.commit();
    } catch (e) {
      console.error('aiCoachChat: failed to persist assistant message', e);
      throw new HttpsError('internal', 'Failed to save AI response');
    }

    return { sessionId, userMessageId, assistantMessageId, reply };
  },
);

function _validateInput(data: unknown): ChatInput {
  if (typeof data !== 'object' || data === null) {
    throw new HttpsError('invalid-argument', 'Body must be an object');
  }
  const d = data as Record<string, unknown>;
  const message = d.message;
  if (typeof message !== 'string' || message.trim() === '') {
    throw new HttpsError('invalid-argument', 'message must be a non-empty string');
  }
  const sessionId = d.sessionId;
  if (sessionId !== undefined && sessionId !== null && typeof sessionId !== 'string') {
    throw new HttpsError('invalid-argument', 'sessionId must be a string');
  }
  return {
    message: message.trim(),
    sessionId: typeof sessionId === 'string' && sessionId !== '' ? sessionId : undefined,
  };
}

/**
 * Builds the RAG context for the coach. Each Firestore fetch is wrapped
 * in `try/catch` and degrades to empty data on failure — a partial
 * outage shouldn't kill the chat.
 */
export async function buildCoachContext(uid: string): Promise<CoachContext> {
  const db = admin.firestore();
  const userRef = db.doc(`users/${uid}`);
  const now = new Date();
  const since = new Date(now.getTime() - RECENT_TX_WINDOW_DAYS * 24 * 60 * 60 * 1000);

  const [
    userSnap,
    walletsSnap,
    transactionsSnap,
    budgetsSnap,
    goalsSnap,
    categoriesSnap,
  ] = await Promise.all([
    userRef.get().catch((e) => {
      console.warn('buildCoachContext: user fetch failed', e);
      return null;
    }),
    userRef
      .collection('wallets')
      .get()
      .catch((e) => {
        console.warn('buildCoachContext: wallets fetch failed', e);
        return null;
      }),
    userRef
      .collection('transactions')
      // `date` is written as a Firestore Timestamp by the client sync
      // mapper (transactionToFirestore in sync_mappers.dart). Comparing
      // against a Timestamp here is required — passing an ISO string
      // silently returns zero rows.
      .where('date', '>=', admin.firestore.Timestamp.fromDate(since))
      .get()
      .catch((e) => {
        console.warn('buildCoachContext: transactions fetch failed', e);
        return null;
      }),
    userRef
      .collection('budgets')
      .get()
      .catch((e) => {
        console.warn('buildCoachContext: budgets fetch failed', e);
        return null;
      }),
    userRef
      .collection('goals')
      .where('completedAt', '==', null)
      .get()
      .catch((e) => {
        console.warn('buildCoachContext: goals fetch failed', e);
        return null;
      }),
    userRef
      .collection('categories')
      .get()
      .catch((e) => {
        console.warn('buildCoachContext: categories fetch failed', e);
        return null;
      }),
  ]);

  const defaultCurrency = _str(userSnap?.data()?.defaultCurrency, 'NGN');

  // Category id → name map for transaction enrichment.
  const categoryNames = new Map<string, string>();
  categoriesSnap?.forEach((d) => {
    const data = d.data();
    const name = _str(data.name, '');
    if (name) categoryNames.set(d.id, name);
  });

  // Wallets (non-archived).
  const wallets = (walletsSnap?.docs ?? [])
    .map((d) => d.data())
    .filter((w) => w.isArchived !== true)
    .map((w) => ({
      id: _str(w.id, ''),
      name: _str(w.name, ''),
      balance: _num(w.balance, 0),
      currency: _str(w.currency, defaultCurrency),
    }));

  // Transactions in the recent window.
  const transactions = (transactionsSnap?.docs ?? []).map((d) => d.data());

  let income = 0;
  let expense = 0;
  const catSpend = new Map<string, number>();
  const merchantSpend = new Map<string, number>();

  for (const t of transactions) {
    const type = _str(t.type, '');
    const amount = _num(t.amount, 0);
    if (type === 'income') {
      income += amount;
    } else if (type === 'expense') {
      expense += amount;
      const catId = _str(t.categoryId, '');
      if (catId) {
        const catName = categoryNames.get(catId) ?? catId;
        catSpend.set(catName, (catSpend.get(catName) ?? 0) + amount);
      }
      const note = _str(t.note, '').trim();
      if (note) {
        merchantSpend.set(note, (merchantSpend.get(note) ?? 0) + amount);
      }
    }
  }

  const topCategories = _topN(catSpend, 5);
  const topMerchants = _topN(merchantSpend, 5);

  // Active budgets — startDate <= now <= endDate (or endDate is null).
  const nowIso = now.toISOString();
  const budgets = (budgetsSnap?.docs ?? [])
    .map((d) => d.data())
    .filter((b) => {
      const start = _str(b.startDate, '');
      const end = _str(b.endDate, '');
      const startsOk = !start || start <= nowIso;
      const endsOk = !end || end >= nowIso;
      return startsOk && endsOk;
    })
    .map((b) => ({
      name: _str(b.name, 'Budget'),
      spent: _num(b.spent, 0),
      total: _num(b.amount, _num(b.total, 0)),
      currency: _str(b.currency, defaultCurrency),
    }));

  const goals = (goalsSnap?.docs ?? [])
    .map((d) => d.data())
    .map((g) => ({
      name: _str(g.name, 'Goal'),
      current: _num(g.currentAmount, _num(g.current, 0)),
      target: _num(g.targetAmount, _num(g.target, 0)),
      currency: _str(g.currency, defaultCurrency),
    }));

  // Cap to most-recent 20 transactions in the prompt to keep tokens sane.
  const recentTransactions = transactions
    .slice()
    .sort((a, b) => _dateIso(b.date, '').localeCompare(_dateIso(a.date, '')))
    .slice(0, 20)
    .map((t) => ({
      note: _str(t.note, ''),
      amount: _num(t.amount, 0),
      categoryName: categoryNames.get(_str(t.categoryId, '')),
      date: _dateIso(t.date, ''),
    }));

  return {
    defaultCurrency,
    totals: { income, expense, net: income - expense },
    wallets,
    topCategories,
    topMerchants,
    budgets,
    goals,
    recentTransactions,
  };
}

/**
 * Last [HISTORY_LIMIT] messages in this session, excluding the just-written
 * user message (we fold that in via the user prompt's "Current question").
 * Returned in chronological order (oldest first) for natural transcripts.
 */
async function _fetchHistory(
  messagesRef: FirebaseFirestore.CollectionReference,
  excludeId: string,
): Promise<CoachHistoryMsg[]> {
  try {
    const snap = await messagesRef
      .orderBy('createdAt', 'desc')
      .limit(HISTORY_LIMIT + 1)
      .get();
    const out: CoachHistoryMsg[] = [];
    for (const d of snap.docs) {
      if (d.id === excludeId) continue;
      const data = d.data();
      const role = data.role;
      const content = data.content;
      if ((role === 'user' || role === 'assistant') && typeof content === 'string') {
        out.push({ role, content });
      }
      if (out.length >= HISTORY_LIMIT) break;
    }
    return out.reverse();
  } catch (e) {
    console.warn('aiCoachChat: history fetch failed', e);
    return [];
  }
}

function _str(v: unknown, fallback: string): string {
  return typeof v === 'string' ? v : fallback;
}

/// Normalises Firestore date fields to an ISO string. Client sync mappers
/// write `date` as a Firestore Timestamp (sync_mappers.dart), but legacy
/// rows or server-only writes may be ISO strings — handle both.
function _dateIso(v: unknown, fallback: string): string {
  if (typeof v === 'string') return v;
  if (v instanceof admin.firestore.Timestamp) {
    return v.toDate().toISOString();
  }
  return fallback;
}

function _num(v: unknown, fallback: number): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}

function _topN(
  m: Map<string, number>,
  n: number,
): Array<{ name: string; amount: number }> {
  return Array.from(m.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, n)
    .map(([name, amount]) => ({ name, amount }));
}
