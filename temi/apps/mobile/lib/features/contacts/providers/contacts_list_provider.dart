import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../data/local/app_database.dart';

/// All contacts owned by the current user, sorted by `name`
/// (case-insensitive). Drift is the source of truth; the sync engine
/// keeps Firestore in lockstep.
final contactsListProvider = StreamProvider<List<Contact>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(contactDaoProvider).watchAll().map(
        (rows) => rows.where((c) => c.userId == user.uid).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      );
});
