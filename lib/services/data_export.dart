import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/weight_service.dart';

/// "Download my data": the food log and weigh-ins as one CSV file that
/// opens in Excel, Numbers or Google Sheets.
class DataExport {
  DataExport._();

  /// One CSV cell: quoted when it holds a comma, quote or line break, and
  /// with a leading ' when it starts like a formula (so a food called
  /// "=SUM(...)" can't run in a spreadsheet).
  static String cell(Object? value) {
    var s = value == null ? '' : '$value';
    if (s.isNotEmpty && '=+-@\t\r'.contains(s[0]) && !_isNumber(s)) {
      s = "'$s";
    }
    if (s.contains(',') ||
        s.contains('"') ||
        s.contains('\n') ||
        s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static bool _isNumber(String s) => double.tryParse(s) != null;

  static String _num(Object? v) {
    final d = BalanceService.number(v);
    if (d == null) return '';
    final r = (d * 10).round() / 10;
    return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
  }

  static String _row(List<Object?> cells) => cells.map(cell).join(',');

  /// Builds the file. [foods] are `user_food` documents; recipe
  /// ingredients (not food eaten) are left out. Rows are oldest first.
  static String csv({
    required List<Map<String, dynamic>> foods,
    required List<WeighIn> weighIns,
  }) {
    final eaten = [
      for (final f in foods)
        if (BalanceService.isLogEntry(f)) f
    ];
    DateTime at(Map<String, dynamic> f) =>
        BalanceService.entryDate(f) ?? DateTime.fromMillisecondsSinceEpoch(0);
    eaten.sort((a, b) => at(a).compareTo(at(b)));

    final b = StringBuffer();
    b.writeln('Food log');
    b.writeln(_row([
      'date',
      'meal',
      'food',
      'portion',
      'kcal',
      'protein_g',
      'carbs_g',
      'fat_g',
    ]));
    for (final f in eaten) {
      final date = BalanceService.entryDate(f);
      b.writeln(_row([
        date == null ? '' : BalanceService.dateKey(date),
        FoodLog.mealOf(f['foodCategory']),
        f['food_description'] ?? '',
        f['food_portion'] ?? '',
        _num(f['food_calories']),
        _num(f['food_protein']),
        _num(f['food_carbs']),
        _num(f['food_fat']),
      ]));
    }
    b.writeln();
    b.writeln('Weigh-ins');
    b.writeln(_row(['date', 'weight_kg']));
    for (final w in weighIns) {
      b.writeln(_row([w.dateKey, w.kg.toStringAsFixed(2)]));
    }
    return b.toString();
  }
}
