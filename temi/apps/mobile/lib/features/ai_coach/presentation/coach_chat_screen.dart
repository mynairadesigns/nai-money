import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../billing/widgets/upsell_sheet.dart';
import '../data/chat_message.dart';
import '../providers/chat_controller.dart';
import '../providers/chat_providers.dart';

/// Ceiling on a single outbound chat message. The callable bills a quota
/// unit per send regardless of size, so an unbounded paste is pure cost.
const _kMaxMessageLength = 1000;

/// AI Coach chat surface (PRD §11.6).
///
/// Empty state: brand hero + 4 suggested prompts. Tapping a prompt
/// immediately sends it (no extra confirmation). Once a session exists,
/// renders the message stream + composer.
class CoachChatScreen extends ConsumerStatefulWidget {
  const CoachChatScreen({super.key});

  @override
  ConsumerState<CoachChatScreen> createState() => _CoachChatScreenState();
}

class _CoachChatScreenState extends ConsumerState<CoachChatScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int _lastMessageCount = 0;

  /// Optimistic local copy of the in-flight user message. Renders as a
  /// bubble immediately on tap so users see instant feedback while the
  /// server writes + the Firestore stream catches up (~1-2s round-trip).
  /// Cleared after sendMessage resolves — by then the stream has the
  /// real persisted message.
  String? _pendingUserMessage;

  static const List<String> _suggestedPrompts = [
    'What did I spend the most on this month?',
    'Am I on track with my budgets?',
    'Where can I cut back?',
    'How close am I to my savings goals?',
  ];

  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? overrideText]) async {
    var text = (overrideText ?? _inputCtrl.text).trim();
    if (text.isEmpty) return;
    // The field caps typed input; this also covers the quick-prompt path.
    if (text.length > _kMaxMessageLength) {
      text = text.substring(0, _kMaxMessageLength);
    }
    _inputCtrl.clear();
    setState(() => _pendingUserMessage = text);
    _scrollToBottom();
    try {
      await ref.read(chatControllerProvider.notifier).sendMessage(text);
    } finally {
      if (mounted) {
        setState(() => _pendingUserMessage = null);
      }
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _newConversation() {
    ref.read(currentSessionIdProvider.notifier).reset();
    _lastMessageCount = 0;
    _pendingUserMessage = null;
    _inputCtrl.clear();
  }

  static const _kQuotaMessage = 'AI quota reached for this month';

  String _errorMessageFor(Object error) {
    if (error is FirebaseFunctionsException) {
      final code = error.code;
      if (code == 'resource-exhausted' ||
          (error.message?.toLowerCase().contains('quota') ?? false)) {
        return _kQuotaMessage;
      }
    }
    return "Couldn't reach Coach Tems";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessionId = ref.watch(currentSessionIdProvider);
    final controllerState = ref.watch(chatControllerProvider);

    // Surface send errors as a SnackBar.
    ref.listen<AsyncValue<void>>(chatControllerProvider, (prev, next) {
      if (next.hasError && !next.isLoading) {
        final msg = _errorMessageFor(next.error!);
        if (msg == _kQuotaMessage) {
          // Free allowance used up → offer Premium instead of a dead end.
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          showUpsellSheet(context, UpsellReason.ai);
          return;
        }
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(msg)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: const Text('Coach Tems'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'new') _newConversation();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new', child: Text('New conversation')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: sessionId == null && _pendingUserMessage == null
                  ? _EmptyState(
                      prompts: _suggestedPrompts,
                      // Skip writing to _inputCtrl — that triggers a
                      // listener-driven setState rebuild for a long
                      // string AND a second rebuild when _send clears
                      // it. Passing the prompt directly is instant.
                      onPromptTap: _send,
                    )
                  : _MessagesList(
                      sessionId: sessionId,
                      scrollController: _scroll,
                      isLoading: controllerState.isLoading,
                      pendingUserMessage: _pendingUserMessage,
                      onMessageCountChanged: (count) {
                        if (count != _lastMessageCount) {
                          _lastMessageCount = count;
                          _scrollToBottom();
                        }
                      },
                    ),
            ),
            _Composer(
              controller: _inputCtrl,
              enabled: !controllerState.isLoading,
              hasText: _inputCtrl.text.trim().isNotEmpty,
              onSend: _send,
              theme: theme,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.prompts, required this.onPromptTap});
  final List<String> prompts;
  final ValueChanged<String> onPromptTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: const BrandLogo(size: 96)),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Ask me anything about your money.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'I see your wallets, recent transactions, budgets, and goals.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.center,
              children: [
                for (final p in prompts)
                  ActionChip(
                    label: Text(p),
                    onPressed: () => onPromptTap(p),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagesList extends ConsumerWidget {
  const _MessagesList({
    required this.sessionId,
    required this.scrollController,
    required this.isLoading,
    required this.onMessageCountChanged,
    this.pendingUserMessage,
  });

  /// Non-null on the first turn of a fresh session — before the server
  /// returns we don't yet have a sessionId to subscribe to.
  final String? sessionId;
  final ScrollController scrollController;
  final bool isLoading;
  final ValueChanged<int> onMessageCountChanged;

  /// Optimistic in-flight user message. Renders as the last bubble until
  /// the stream catches up with the persisted copy.
  final String? pendingUserMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // No sessionId yet (first-turn flight) — render only the optimistic
    // bubble + typing indicator. The stream subscribes once the server
    // returns a sessionId.
    if (sessionId == null) {
      return _buildOptimisticOnly();
    }
    final messagesAsync = ref.watch(chatMessagesProvider(sessionId));

    return messagesAsync.when(
      loading: () => _buildOptimisticOnly(fallbackSpinner: true),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            "Couldn't load conversation.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ),
      data: (messages) {
        // Suppress the optimistic bubble once the stream has it
        // (matching role='user' AND content). Otherwise we'd briefly
        // see duplicates between server-persist and Future await.
        final showPending = pendingUserMessage != null &&
            !messages.any((m) =>
                m.role == 'user' && m.content == pendingUserMessage);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onMessageCountChanged(messages.length + (showPending ? 1 : 0));
        });
        final pendingCount = showPending ? 1 : 0;
        final indicatorCount = isLoading ? 1 : 0;
        final itemCount = messages.length + pendingCount + indicatorCount;
        return ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          itemCount: itemCount,
          separatorBuilder: (_, _) =>
              const SizedBox(height: AppSpacing.sm),
          itemBuilder: (_, index) {
            if (index < messages.length) {
              return _MessageBubble(message: messages[index]);
            }
            final tailIndex = index - messages.length;
            if (showPending && tailIndex == 0) {
              return _OptimisticUserBubble(text: pendingUserMessage!);
            }
            return const _TypingIndicator();
          },
        );
      },
    );
  }

  /// Renders only the optimistic user bubble + typing indicator. Used
  /// when there's no Firestore stream subscription yet (sessionId null)
  /// OR when the stream is still in its initial loading state.
  Widget _buildOptimisticOnly({bool fallbackSpinner = false}) {
    if (pendingUserMessage == null) {
      return fallbackSpinner
          ? const Center(child: CircularProgressIndicator())
          : const SizedBox.shrink();
    }
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      children: [
        _OptimisticUserBubble(text: pendingUserMessage!),
        const SizedBox(height: AppSpacing.sm),
        if (isLoading) const _TypingIndicator(),
      ],
    );
  }
}

class _OptimisticUserBubble extends StatelessWidget {
  const _OptimisticUserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Opacity(
          // Slightly muted to hint "in flight" — the stream-confirmed
          // version pops to full opacity within ~1s when it arrives.
          opacity: 0.85,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: AppBorderRadius.lg,
            ),
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (message.role == 'system') {
      return Center(
        child: Text(
          message.content,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final isUser = message.role == 'user';
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.8,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainer,
          borderRadius: AppBorderRadius.lg,
        ),
        child: Text(
          message.content,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isUser
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );

    if (isUser) {
      return Align(alignment: Alignment.centerRight, child: bubble);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.auto_awesome,
            size: 14,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(child: bubble),
      ],
    );
  }
}

/// Three bouncing dots wrapped in an assistant-style bubble. Used as
/// a transient "typing…" affordance while the callable is in flight.
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.auto_awesome,
              size: 14, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: AppBorderRadius.lg,
          ),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.xs),
                    _dot(theme, i),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _dot(ThemeData theme, int index) {
    final phase = (_ctrl.value - index * 0.2) % 1.0;
    final scale = 0.6 + 0.4 * (1 - (phase * 2 - 1).abs());
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurfaceVariant,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.hasText,
    required this.onSend,
    required this.theme,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool hasText;
  final VoidCallback onSend;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                // Every message costs a quota unit and provider tokens, so
                // a pasted wall of text gets capped rather than billed.
                maxLength: _kMaxMessageLength,
                textInputAction: TextInputAction.newline,
                enabled: enabled,
                decoration: const InputDecoration(
                  hintText: 'Ask Coach Tems...',
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              height: 48,
              width: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppBorderRadius.base,
                  ),
                ),
                onPressed: (hasText && enabled) ? onSend : null,
                child: const Icon(Icons.arrow_upward),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
