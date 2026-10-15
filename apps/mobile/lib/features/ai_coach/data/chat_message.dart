import 'package:cloud_firestore/cloud_firestore.dart';

/// One message inside an AI coach chat session.
///
/// Persisted server-side at
/// `users/{uid}/aiChats/{sessionId}/messages/{msgId}` by the
/// `aiCoachChat` callable. The client never writes these docs directly —
/// it only streams them for display.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  /// Firestore doc id.
  final String id;

  /// Parent session id (matches the doc's path segment).
  final String sessionId;

  /// One of: `'user'`, `'assistant'`, `'system'`.
  final String role;

  /// Plain-text message body. Markdown is not parsed in v1.
  final String content;

  /// Server timestamp the message was written at.
  final DateTime createdAt;

  /// Hydrate a [ChatMessage] from a Firestore message doc.
  ///
  /// Tolerant to a missing `createdAt` (Firestore server timestamps are
  /// briefly `null` between local optimistic insert and server ack —
  /// although in our model the server always writes them, this keeps
  /// streams flicker-free during cold start).
  factory ChatMessage.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final raw = data['createdAt'];
    final created = raw is Timestamp
        ? raw.toDate()
        : raw is DateTime
            ? raw
            : DateTime.now();
    return ChatMessage(
      id: doc.id,
      sessionId: data['sessionId'] as String? ?? doc.reference.parent.parent?.id ?? '',
      role: data['role'] as String? ?? 'assistant',
      content: data['content'] as String? ?? '',
      createdAt: created,
    );
  }
}
