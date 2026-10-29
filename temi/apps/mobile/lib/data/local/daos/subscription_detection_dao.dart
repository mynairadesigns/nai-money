import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/subscription_detections.dart';

part 'subscription_detection_dao.g.dart';

@DriftAccessor(tables: [SubscriptionDetections])
class SubscriptionDetectionDao extends DatabaseAccessor<AppDatabase>
    with _$SubscriptionDetectionDaoMixin {
  SubscriptionDetectionDao(super.db);

  Stream<List<SubscriptionDetection>> watchAll() =>
      select(subscriptionDetections).watch();

  Future<SubscriptionDetection?> getById(String id) =>
      (select(subscriptionDetections)..where((s) => s.id.equals(id)))
          .getSingleOrNull();

  Future<void> insertOne(SubscriptionDetectionsCompanion row) =>
      into(subscriptionDetections).insert(row);

  Future<bool> updateOne(SubscriptionDetectionsCompanion row) =>
      update(subscriptionDetections).replace(row);

  Future<int> deleteById(String id) =>
      (delete(subscriptionDetections)..where((s) => s.id.equals(id))).go();
}
