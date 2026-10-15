// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subscription_detection_dao.dart';

// ignore_for_file: type=lint
mixin _$SubscriptionDetectionDaoMixin on DatabaseAccessor<AppDatabase> {
  $SubscriptionDetectionsTable get subscriptionDetections =>
      attachedDatabase.subscriptionDetections;
  SubscriptionDetectionDaoManager get managers =>
      SubscriptionDetectionDaoManager(this);
}

class SubscriptionDetectionDaoManager {
  final _$SubscriptionDetectionDaoMixin _db;
  SubscriptionDetectionDaoManager(this._db);
  $$SubscriptionDetectionsTableTableManager get subscriptionDetections =>
      $$SubscriptionDetectionsTableTableManager(
        _db.attachedDatabase,
        _db.subscriptionDetections,
      );
}
