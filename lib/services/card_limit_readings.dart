import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sms_import.dart';

/// What a card's bank last said was left of its credit limit: the "Avl Lmt"
/// a card alert quotes, with the card's last digits and when it was sent.
class LimitReading {
  final String last4;
  final int amount;
  final DateTime at;
  const LimitReading(
      {required this.last4, required this.amount, required this.at});

  Map<String, dynamic> toJson() =>
      {'last4': last4, 'amount': amount, 'at': at.toIso8601String()};

  static LimitReading? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['at']}');
    final amount = j['amount'];
    final last4 = j['last4'];
    if (at == null || amount is! int || last4 is! String) return null;
    return LimitReading(last4: last4, amount: amount, at: at);
  }
}

/// The latest available-limit reading per card, kept on the device from SMS
/// scans so the Credit cards screen can check its figures against the
/// bank's. Only the number, the card's digits and the time are kept — never
/// the message.
class CardLimitReadings {
  static const _key = 'cardLimitReadings';

  /// The same store for a card's reward points balance, as alerts and
  /// statements quote it ("Reward Points balance: 12,345").
  static const points = CardReadingStore('cardPointsReadings');

  /// Every card's latest reading, by its last digits.
  static Future<Map<String, LimitReading>> load() =>
      const CardReadingStore(_key).load();

  /// Keeps the newest of [readings] and those already saved, per card.
  static Future<void> record(Iterable<LimitReading> readings) =>
      const CardReadingStore(_key).record(readings);

  /// The reading in a message, when it quotes an available limit and names
  /// the card.
  static LimitReading? fromSms(String body, DateTime receivedAt) {
    final found = SmsImport.availableLimitOf(body);
    if (found == null || found.last4 == null) return null;
    return LimitReading(
        last4: found.last4!, amount: found.amount, at: receivedAt);
  }

  /// The reward points balance a message quotes, for the card it names.
  static LimitReading? pointsFromSms(String body, DateTime receivedAt) {
    final found = SmsImport.rewardPointsOf(body);
    if (found == null || found.last4 == null) return null;
    return LimitReading(
        last4: found.last4!, amount: found.points, at: receivedAt);
  }

  /// The reading for a card ending in [last4], if any.
  static LimitReading? forCard(Map<String, LimitReading> all, String? last4) {
    if (last4 == null) return null;
    LimitReading? best;
    for (final r in all.values) {
      if (!SmsImport.sameAccountRef(r.last4, last4)) continue;
      if (best == null || r.at.isAfter(best.at)) best = r;
    }
    return best;
  }
}

/// Latest reading per card, kept in shared preferences under [key].
class CardReadingStore {
  final String key;
  const CardReadingStore(this.key);

  Future<Map<String, LimitReading>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (LimitReading.fromJson(e.value) case final r?) '${e.key}': r
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> record(Iterable<LimitReading> readings) async {
    if (readings.isEmpty) return;
    final all = await load();
    var changed = false;
    for (final r in readings) {
      final old = all[r.last4];
      if (old == null || r.at.isAfter(old.at)) {
        all[r.last4] = r;
        changed = true;
      }
    }
    if (!changed) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          key, jsonEncode({for (final e in all.entries) e.key: e.value}));
    } catch (_) {}
  }
}
