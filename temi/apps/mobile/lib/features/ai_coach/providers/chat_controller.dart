import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/remote/ai_service.dart';
import 'chat_providers.dart';

/// Drives the AI coach send-message flow.
///
/// The actual chat persistence happens server-side: the `aiCoachChat`
/// callable writes both the user and assistant message docs under
/// `users/{uid}/aiChats/{sessionId}/messages/`. This controller only
/// invokes the callable and reflects pending/error state to the UI.
///
/// On the first turn of a fresh session, the server generates the
/// session id and returns it; we mirror it into [currentSessionIdProvider]
/// so [chatMessagesProvider] can subscribe to the new path.
class ChatController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final currentId = ref.read(currentSessionIdProvider);
      final result = await ref.read(aiServiceProvider).coachChat(
            message: trimmed,
            sessionId: currentId,
          );
      // Server may have generated a fresh session id on turn 1.
      if (currentId != result.sessionId) {
        ref.read(currentSessionIdProvider.notifier).set(result.sessionId);
      }
    });
  }
}

final chatControllerProvider =
    AsyncNotifierProvider<ChatController, void>(ChatController.new);
