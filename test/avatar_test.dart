// Avatars: ready-made ones, photos, and back to the initial (the default).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/avatar_service.dart';

import 'test_helpers.dart';

void main() {
  late TestWorld w;
  const me = TestWorld.uid;

  setUp(() async {
    w = TestWorld()..install();
    await w.db.collection('users').doc(me).set({'email': 'me@example.com'});
  });
  tearDown(TestWorld.uninstall);

  Future<Map<String, dynamic>?> stored() async =>
      Avatars.fromUser((await w.db.collection('users').doc(me).get()).data());

  test('no avatar means the initial-letter default', () async {
    expect(await stored(), isNull);
    expect(Avatars.fromUser(null), isNull);
    expect(Avatars.fromUser({'avatar': 'junk'}), isNull);
    expect(Avatars.fromUser({'avatar': {'preset': 'not-a-preset'}}), isNull);
  });

  test('pick a ready-made one, then go back to your initial', () async {
    await Avatars.setPreset(me, 'avocado');
    expect(await stored(), {'preset': 'avocado'});
    expect(await Avatars.forUid(me), {'preset': 'avocado'});

    await Avatars.useInitials(me);
    expect(await stored(), isNull);
    expect(await Avatars.forUid(me), isNull);
  });

  test('a photo replaces a preset', () async {
    await Avatars.setPreset(me, 'fox');
    await Avatars.setPhoto(me, Uint8List.fromList([1, 2, 3]));
    final a = await stored();
    expect(a?.containsKey('preset'), isFalse);
    expect(a?['photo'], isA<String>());
  });

  test('photos that are too big are refused', () {
    expect(
      () => Avatars.setPhoto(
          me, Uint8List(Avatars.maxPhotoBytes + 1)),
      throwsA(isA<AvatarTooBig>()),
    );
  });

  test('every preset has a unique id', () {
    final ids = {for (final p in Avatars.presets) p.id};
    expect(ids.length, Avatars.presets.length);
  });
}
