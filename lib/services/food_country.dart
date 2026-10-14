import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

/// The country foods are looked up for: sizes, brands, products and
/// labels differ between countries (a can of Coke is 330ml in the UK and
/// 355ml in the US). The person's choice in Profile settings
/// (`users/{uid}.food_country`), otherwise the phone or browser's region,
/// otherwise the UK.
class FoodCountry {
  FoodCountry._();

  static const fallback = 'GB';

  /// Countries to pick from, by name. Any other two-letter code still
  /// works if it comes from the device.
  static const countries = <String, String>{
    'GB': 'United Kingdom',
    'IE': 'Ireland',
    'US': 'United States',
    'CA': 'Canada',
    'AU': 'Australia',
    'NZ': 'New Zealand',
    'ZA': 'South Africa',
    'IN': 'India',
    'PK': 'Pakistan',
    'BD': 'Bangladesh',
    'LK': 'Sri Lanka',
    'SG': 'Singapore',
    'MY': 'Malaysia',
    'PH': 'Philippines',
    'HK': 'Hong Kong',
    'JP': 'Japan',
    'KR': 'South Korea',
    'CN': 'China',
    'TH': 'Thailand',
    'ID': 'Indonesia',
    'VN': 'Vietnam',
    'AE': 'United Arab Emirates',
    'SA': 'Saudi Arabia',
    'QA': 'Qatar',
    'IL': 'Israel',
    'TR': 'Turkey',
    'EG': 'Egypt',
    'NG': 'Nigeria',
    'KE': 'Kenya',
    'GH': 'Ghana',
    'FR': 'France',
    'DE': 'Germany',
    'ES': 'Spain',
    'PT': 'Portugal',
    'IT': 'Italy',
    'NL': 'Netherlands',
    'BE': 'Belgium',
    'LU': 'Luxembourg',
    'CH': 'Switzerland',
    'AT': 'Austria',
    'DK': 'Denmark',
    'SE': 'Sweden',
    'NO': 'Norway',
    'FI': 'Finland',
    'IS': 'Iceland',
    'PL': 'Poland',
    'CZ': 'Czechia',
    'SK': 'Slovakia',
    'HU': 'Hungary',
    'RO': 'Romania',
    'BG': 'Bulgaria',
    'GR': 'Greece',
    'CY': 'Cyprus',
    'MT': 'Malta',
    'HR': 'Croatia',
    'SI': 'Slovenia',
    'RS': 'Serbia',
    'LT': 'Lithuania',
    'LV': 'Latvia',
    'EE': 'Estonia',
    'UA': 'Ukraine',
    'MX': 'Mexico',
    'BR': 'Brazil',
    'AR': 'Argentina',
    'CL': 'Chile',
    'CO': 'Colombia',
    'PE': 'Peru',
    'JM': 'Jamaica',
    'TT': 'Trinidad and Tobago',
  };

  static String? _chosen;

  /// Whose choice [_chosen] is (so signing in as someone else reloads).
  static String? _loadedFor;

  static String? get _uid {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null; // Firebase not set up (tests)
    }
  }

  static bool get _current => _loadedFor != null && _loadedFor == _uid;

  /// The code in use now.
  static String get code => (_current ? _chosen : null) ?? deviceCountry;

  /// The phone or browser's region, if it has one.
  static String get deviceCountry {
    final cc = (WidgetsBinding.instance.platformDispatcher.locale.countryCode ??
            '')
        .toUpperCase();
    return RegExp(r'^[A-Z]{2}$').hasMatch(cc) ? cc : fallback;
  }

  /// Whether the person picked it (rather than it coming from the device).
  static bool get chosen => _current && _chosen != null;

  static String nameOf(String cc) => countries[cc] ?? cc;

  static String? _valid(Object? v) {
    final cc = '${v ?? ''}'.trim().toUpperCase();
    return RegExp(r'^[A-Z]{2}$').hasMatch(cc) ? cc : null;
  }

  /// Reads their choice once (quick: Firestore keeps a copy on the device).
  static Future<void> ensureLoaded() async {
    if (_current) return;
    final uid = _uid;
    if (uid == null) return;
    try {
      final data = (await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get())
          .data();
      _chosen = _valid(data?['food_country']);
      _loadedFor = uid;
    } catch (_) {}
  }

  /// Saves their choice (null goes back to the device's region).
  static Future<void> choose(String? cc) async {
    final uid = _uid;
    if (uid == null) return;
    final valid = _valid(cc);
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'food_country': valid ?? FieldValue.delete(),
    }, SetOptions(merge: true));
    _chosen = valid;
    _loadedFor = uid;
  }
}
