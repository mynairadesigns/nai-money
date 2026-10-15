import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/firestore_provider.dart';
import '../data/chat_message.dart';

/// User-controlled "current session" id.
///
/// Starts `null` on first open. The first successful `aiCoachChat`
/// callable response sets it to the server-generated session id via
/// [CurrentSessionId.set]; the "New conversation" menu action resets
/// it back to `null` via [CurrentSessionId.reset].
class CurrentSessionId extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String id) => state = id;
  void reset() => state = null;
}

final currentSessionIdProvider =
    NotifierProvider<CurrentSessionId, String?>(CurrentSessionId.new);

/// Live stream of messages for [sessionId], ordered by `createdAt` asc.
///
/// Returns an empty stream when [sessionId] is `null` (no session yet)
/// or when no user is signed in. Firestore is authoritative for chat;
/// there is no Drift mirror in this slice (CLAUDE.md §8 — chat is
/// inherently online so the offline-first rule is waived).
final chatMessagesProvider =
    StreamProvider.family<List<ChatMessage>, String?>((ref, sessionId) {
  if (sessionId == null) return const Stream.empty();
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final fs = ref.watch(firestoreProvider);
  return fs
      .collection('users/${user.uid}/aiChats/$sessionId/messages')
      .orderBy('createdAt')
      .snapshots()
      .map((snap) => [for (final d in snap.docs) ChatMessage.fromDoc(d)]);
});
