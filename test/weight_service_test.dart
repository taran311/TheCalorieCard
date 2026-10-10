import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/data_export.dart';
import 'package:namer_app/services/weight_service.dart';

import 'test_helpers.dart';

/// Weigh-ins every [everyDays] days for [days] days ending today, starting
/// at [startKg] and changing by [kgPerWeek].
List<WeighIn> series({
  required DateTime today,
  required int days,
  required double startKg,
  required double kgPerWeek,
  int everyDays = 1,
}) {
  final out = <WeighIn>[];
  for (var i = days - 1; i >= 0; i -= everyDays) {
    final d = DateTime(today.year, today.month, today.day - i);
    final kg = startKg + kgPerWeek * (days - 1 - i) / 7;
    out.add(WeighIn(dateKey: BalanceService.dateKey(d), date: d, kg: kg));
  }
  return out;
}

void main() {
  late TestWorld world;

  setUp(() {
    world = TestWorld();
    world.install();
  });

  tearDown(TestWorld.uninstall);

  group('logging', () {
    test('one weigh-in per day: logging again replaces it', () async {
      await WeightService.log(TestWorld.uid, 80.0);
      await WeightService.log(TestWorld.uid, 79.456);
      final snap = await world.db.collection('weigh_ins').get();
      expect(snap.docs, hasLength(1));
      final doc = snap.docs.single;
      expect(doc.id, '${TestWorld.uid}_${world.today}');
      expect(doc.data()['user_id'], TestWorld.uid);
      expect(doc.data()['date_key'], world.today);
      expect(doc.data()['kg'], 79.46);
      expect(doc.data()['created_at'], isNotNull);
    });

    test('history is oldest first and only yours', () async {
      await WeightService.log(TestWorld.uid, 81,
          on: DateTime(2026, 10, 1));
      await WeightService.log(TestWorld.uid, 80);
      await WeightService.log(TestWorld.otherUid, 60);
      final h = await WeightService.history(TestWorld.uid);
      expect(h.map((w) => w.kg), [81, 80]);
      expect(h.first.dateKey, '2026-10-01');
    });

    test('rejects nonsense weights', () async {
      expect(() => WeightService.log(TestWorld.uid, 0), throwsArgumentError);
      expect(() => WeightService.log(TestWorld.uid, double.nan),
          throwsArgumentError);
    });

    test('delete removes that day', () async {
      await WeightService.log(TestWorld.uid, 80);
      await WeightService.delete(TestWorld.uid, world.today);
      expect(await WeightService.history(TestWorld.uid), isEmpty);
    });
  });

  group('trend', () {
    test('7-day average smooths the line', () {
      final pts = series(
          today: world.now, days: 10, startKg: 80, kgPerWeek: 0);
      final s = WeightService.smoothed([
        ...pts.take(9),
        WeighIn(
            dateKey: pts.last.dateKey, date: pts.last.date, kg: 87),
      ]);
      // The last day's jump of 7 kg is spread over the 7-day window.
      expect(s.last, closeTo(81, 1e-9));
      expect(s.first, 80);
    });

    test('weekly trend matches a steady loss', () {
      final pts = series(
          today: world.now, days: 28, startKg: 90, kgPerWeek: -0.5);
      expect(WeightService.weeklyTrend(pts), closeTo(-0.5, 1e-6));
      expect(WeightService.weeklyTrend(pts.take(1).toList()), isNull);
    });

    test('lastDays keeps the window', () {
      final pts = series(
          today: world.now, days: 120, startKg: 80, kgPerWeek: 0);
      final recent = WeightService.lastDays(pts, 90, now: world.now);
      expect(recent, hasLength(90));
    });
  });

  group('check-in', () {
    test('nothing until three weeks of data', () {
      final pts = series(
          today: world.now, days: 14, startKg: 80, kgPerWeek: 0);
      expect(
          WeightService.checkIn(
              history: pts, mode: 'lose', goalKcal: 2000, now: world.now),
          isNull);
    });

    test('losing but flat: suggests 150 kcal less', () {
      final pts = series(
          today: world.now, days: 28, startKg: 80, kgPerWeek: 0, everyDays: 2);
      final c = WeightService.checkIn(
          history: pts,
          mode: 'lose',
          goalKcal: 2000,
          floorKcal: 1500,
          now: world.now)!;
      expect(c.suggestedChange, -150);
      expect(c.onTrack, isFalse);
    });

    test('losing steadily: on track', () {
      final pts = series(
          today: world.now, days: 28, startKg: 80, kgPerWeek: -0.5);
      final c = WeightService.checkIn(
          history: pts, mode: 'lose', goalKcal: 2000, now: world.now)!;
      expect(c.onTrack, isTrue);
      expect(c.kgPerWeek, closeTo(-0.5, 1e-6));
    });

    test('losing fast: suggests eating a little more', () {
      final pts = series(
          today: world.now, days: 28, startKg: 90, kgPerWeek: -1.5);
      final c = WeightService.checkIn(
          history: pts, mode: 'lose', goalKcal: 1800, now: world.now)!;
      expect(c.suggestedChange, 150);
    });

    test('never suggests going below the safe minimum', () {
      final pts = series(
          today: world.now, days: 28, startKg: 70, kgPerWeek: 0.1);
      final atFloor = WeightService.checkIn(
          history: pts,
          mode: 'lose',
          goalKcal: 1250,
          floorKcal: 1200,
          now: world.now)!;
      expect(atFloor.suggestedChange, 0);
      expect(atFloor.atSafeMinimum, isTrue);
      expect(atFloor.onTrack, isFalse);

      final someRoom = WeightService.checkIn(
          history: pts,
          mode: 'lose',
          goalKcal: 1320,
          floorKcal: 1200,
          now: world.now)!;
      expect(someRoom.suggestedChange, -100);
    });

    test('gain and maintain', () {
      final flat = series(
          today: world.now, days: 28, startKg: 70, kgPerWeek: 0);
      expect(
          WeightService.checkIn(
                  history: flat, mode: 'gain', goalKcal: 2800, now: world.now)!
              .suggestedChange,
          150);
      expect(
          WeightService.checkIn(
                  history: flat,
                  mode: 'maintain',
                  goalKcal: 2400,
                  now: world.now)!
              .onTrack,
          isTrue);
      final rising = series(
          today: world.now, days: 28, startKg: 70, kgPerWeek: 0.4);
      expect(
          WeightService.checkIn(
                  history: rising,
                  mode: 'maintain',
                  goalKcal: 2400,
                  now: world.now)!
              .suggestedChange,
          -100);
    });
  });

  group('data export', () {
    test('CSV has the food log and weigh-ins, safely quoted', () async {
      await world.addEntry(
          at: DateTime(2026, 10, 8, 9),
          description: 'Toast, butter',
          meal: 'Breakfast',
          calories: 250.04);
      await world.addEntry(
          at: DateTime(2026, 10, 9, 13), description: '=SUM(A1)');
      await WeightService.log(TestWorld.uid, 80.5);
      final foods = await world.foodRows();
      final csv = DataExport.csv(
        foods: foods,
        weighIns: await WeightService.history(TestWorld.uid),
      );
      final lines = csv.split('\n');
      expect(lines[0], 'Food log');
      expect(lines[1], 'date,meal,food,portion,kcal,protein_g,carbs_g,fat_g');
      expect(lines[2], '2026-10-08,Breakfast,"Toast, butter",,250,10,10,2');
      expect(lines[3], "2026-10-09,Lunch,'=SUM(A1),,100,10,10,2");
      expect(csv, contains('Weigh-ins\ndate,weight_kg\n${world.today},80.50'));
    });

    test('recipe ingredients are left out', () {
      final csv = DataExport.csv(foods: [
        {
          'food_description': 'Flour',
          'foodCategory': BalanceService.recipeCategory,
        }
      ], weighIns: const []);
      expect(csv, isNot(contains('Flour')));
    });
  });
}
