import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wraps [FirebaseStorage] with helpers for the receipt-scanner pipeline
/// (PRD §6.4.1). Buckets receipts under `users/{uid}/receipts/...`, in
/// line with `storage.rules` + CLAUDE.md §8.
///
/// The temp object created by [uploadReceiptTemp] is what the
/// `scanReceipt` Cloud Function fetches via the download URL. After the
/// user saves the parsed transaction, [moveReceiptToPermanent] copies the
/// object to its permanent path (`users/{uid}/receipts/{txId}.jpg`) and
/// deletes the temp.
class StorageService {
  StorageService(this._storage);
  final FirebaseStorage _storage;

  /// Uploads to `users/{uid}/receipts/temp/{id}.jpg`. Returns the
  /// public download URL (for the Function to fetch) and the storage
  /// path (so we can move/delete the temp later).
  Future<({String downloadUrl, String storagePath})> uploadReceiptTemp({
    required String uid,
    required File file,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final path = 'users/$uid/receipts/temp/$id.jpg';
    final ref = _storage.ref(path);
    final task = await ref.putFile(
      file,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final url = await task.ref.getDownloadURL();
    return (downloadUrl: url, storagePath: path);
  }

  /// Copies the temp object to `users/{uid}/receipts/{txId}.jpg`, returns
  /// the new download URL, and best-effort deletes the temp. Firebase
  /// Storage has no native "move", so we round-trip via bytes.
  Future<String> moveReceiptToPermanent({
    required String uid,
    required String txId,
    required String tempStoragePath,
  }) async {
    final tempRef = _storage.ref(tempStoragePath);
    final permanentPath = 'users/$uid/receipts/$txId.jpg';
    final permanentRef = _storage.ref(permanentPath);
    final bytes = await tempRef.getData();
    if (bytes == null) {
      throw StateError('Temp receipt $tempStoragePath was empty or missing');
    }
    await permanentRef.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final url = await permanentRef.getDownloadURL();
    try {
      await tempRef.delete();
    } catch (_) {
      // Best-effort cleanup; ignore if already gone.
    }
    return url;
  }

  /// Best-effort delete of a temp receipt — used when the user cancels
  /// out of the form before saving.
  Future<void> deleteTempReceipt(String tempStoragePath) async {
    try {
      await _storage.ref(tempStoragePath).delete();
    } catch (_) {
      // Best-effort.
    }
  }
}

final firebaseStorageProvider = Provider<FirebaseStorage>(
  (_) => FirebaseStorage.instance,
);

final storageServiceProvider = Provider<StorageService>(
  (ref) => StorageService(ref.watch(firebaseStorageProvider)),
);
