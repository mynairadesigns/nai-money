import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Android notification channel used for all local notifications.
const _kChannelId = 'homa_alerts';
const _kChannelName = 'Homa Finance Alerts';
const _kChannelDesc = 'Budget, bill, debt, and goal reminders';

/// Wraps [FlutterLocalNotificationsPlugin] with a clean API for the rest of
/// the app. Call [init] once at startup (via [notificationCoordinatorProvider])
/// before using any other method.
class NotificationService {
  NotificationService() : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialised = false;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    // flutter_local_notifications has no web implementation. Leaving
    // `_initialised == false` makes every show/schedule call a no-op.
    if (_initialised || kIsWeb) return;

    // Timezone: initialise the database, then GUARANTEE `tz.local` is set.
    // We seed it with UTC first (always a valid location) so the late
    // `tz.local` is never uninitialised — otherwise `scheduleAt`'s
    // `TZDateTime.from(when, tz.local)` throws a LateInitializationError on
    // systems whose abbreviation (`DateTime.now().timeZoneName`) doesn't map
    // to a tz database key. We then refine to the matched zone if we find one.
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('UTC'));
      final localName = DateTime.now().timeZoneName;
      final match = tz.timeZoneDatabase.locations.keys
          .where((k) => k.contains(localName))
          .firstOrNull;
      if (match != null) {
        tz.setLocalLocation(tz.getLocation(match));
      }
    } catch (_) {
      // tz.local stays at UTC — scheduled times may be off by the UTC offset
      // in this edge case, but scheduling will never crash.
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false, // We ask explicitly via requestPermissions
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    // Guard the plugin calls: in a unit-test environment the platform channel
    // isn't registered, and we never want notification setup to throw out of
    // init() (the coordinator treats a throw as fatal-and-logs). A failure
    // here just leaves `_initialised == false`, so later show/schedule calls
    // no-op gracefully.
    try {
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: darwin),
      );
      // Create the Android notification channel (no-op on iOS).
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _kChannelId,
              _kChannelName,
              description: _kChannelDesc,
              importance: Importance.defaultImportance,
            ),
          );
      _initialised = true;
    } catch (e) {
      debugPrint('NotificationService.init: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Permission
  // ---------------------------------------------------------------------------

  /// Requests notification permission on iOS and Android 13+.
  /// Returns `true` if granted (or platform doesn't require runtime ask).
  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final granted = await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        return granted ?? false;
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final granted = await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
        return granted ?? false;
      }
    } catch (e) {
      debugPrint('NotificationService.requestPermissions: $e');
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Show / schedule
  // ---------------------------------------------------------------------------

  /// Shows an immediate notification.
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialised) return;
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _kChannelId,
            _kChannelName,
            channelDescription: _kChannelDesc,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('NotificationService.showNow($id): $e');
    }
  }

  /// Schedules a notification at [when]. Skips silently if [when] is in the
  /// past. Scheduling the same [id] again replaces the prior one.
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialised) return;
    if (when.isBefore(DateTime.now())) return;
    try {
      final tzWhen = tz.TZDateTime.from(when, tz.local);
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzWhen,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _kChannelId,
            _kChannelName,
            channelDescription: _kChannelDesc,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (e) {
      debugPrint('NotificationService.scheduleAt($id): $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Cancel
  // ---------------------------------------------------------------------------

  Future<void> cancel(int id) async {
    if (!_initialised) return;
    try {
      await _plugin.cancel(id);
    } catch (e) {
      debugPrint('NotificationService.cancel($id): $e');
    }
  }

  Future<void> cancelAll() async {
    if (!_initialised) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('NotificationService.cancelAll: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Deterministic id scheme
  // ---------------------------------------------------------------------------

  /// Returns a stable 31-bit non-negative int notification id for [kind] +
  /// [entityId]. Re-scheduling with the same inputs replaces the prior alert.
  ///
  /// Examples:
  ///   notifId('budget_50',  budgetId)
  ///   notifId('debt_7d',    debtId)
  ///   notifId('goal_75',    goalId)
  ///   notifId('recurring',  ruleId)
  ///   notifId('weekly_recap', 'global')
  int notifId(String kind, String entityId) {
    final raw = '$kind:$entityId';
    var hash = 0;
    for (final unit in raw.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }
}
