import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:namer_app/services/proxy_client.dart';

/// One friend you invited, and how far they've got.
@immutable
class InvitedFriend {
  final String name;

  /// Days they've logged food so far (up to [ReferralStatus.daysNeeded]).
  final int days;

  /// 'pending', 'rewarded' or 'expired'.
  final String status;

  const InvitedFriend(this.name, this.days, this.status);

  bool get rewarded => status == 'rewarded';
  bool get pending => status == 'pending';
}

/// Refer a friend, from the server's `/referral/check`.
@immutable
class ReferralStatus {
  /// Whoever invited you, if you're new: their name and your progress.
  final InvitedFriend? invitedBy;
  final List<InvitedFriend> friends;

  /// Free months you've earned by inviting.
  final int earned;
  final DateTime? bonusUntil;
  final int rewardDays;
  final int daysNeeded;

  const ReferralStatus({
    this.invitedBy,
    this.friends = const [],
    this.earned = 0,
    this.bonusUntil,
    this.rewardDays = 30,
    this.daysNeeded = 3,
  });

  static InvitedFriend? _friend(Object? v) {
    if (v is! Map) return null;
    final days = v['days'];
    return InvitedFriend(
      '${v['name'] ?? 'A friend'}',
      days is num ? days.toInt() : 0,
      '${v['status'] ?? 'pending'}',
    );
  }

  factory ReferralStatus.fromJson(Map<String, dynamic> j) => ReferralStatus(
        invitedBy: _friend(j['invitedBy']),
        friends: [
          for (final f in (j['friends'] is List ? j['friends'] as List : []))
            if (_friend(f) case final friend?)
              if (friend.status != 'expired') friend,
        ],
        earned: j['earned'] is num ? (j['earned'] as num).toInt() : 0,
        bonusUntil: DateTime.tryParse('${j['bonusUntil'] ?? ''}')?.toLocal(),
        rewardDays: j['rewardDays'] is num ? (j['rewardDays'] as num).toInt() : 30,
        daysNeeded: j['daysNeeded'] is num ? (j['daysNeeded'] as num).toInt() : 3,
      );

  /// "a month" for 30 days, otherwise "N days".
  String get rewardLabel =>
      rewardDays == 30 ? 'a month' : '$rewardDays days';
}

/// Checks invites with the server: records that a new account was invited
/// (its first friend), and hands out the free month once they've logged
/// on enough days. The month itself arrives in `billing`, so
/// [Premium] picks it up by itself.
class Referrals {
  Referrals._();

  static final ValueNotifier<ReferralStatus?> status = ValueNotifier(null);

  static DateTime? _last;
  static Future<void>? _running;

  /// At most every few minutes unless [force]d.
  static Future<void> check({bool force = false}) {
    final last = _last;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 5)) {
      return Future.value();
    }
    return _running ??= _check().whenComplete(() => _running = null);
  }

  static Future<void> _check() async {
    _last = DateTime.now();
    try {
      final r = await ProxyClient.post('/referral/check', const {})
          .timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) return;
      final j = json.decode(r.body);
      if (j is Map<String, dynamic>) status.value = ReferralStatus.fromJson(j);
    } catch (_) {
      // Offline or the server's busy: try again next time.
    }
  }

  static void reset() {
    status.value = null;
    _last = null;
  }
}
