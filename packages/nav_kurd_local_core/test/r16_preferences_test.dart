import 'dart:convert';

import 'package:nav_kurd_local_core/src/core_failure.dart';
import 'package:nav_kurd_local_core/src/local_state.dart';
import 'package:nav_kurd_local_core/src/r16_preferences.dart';
import 'package:test/test.dart';

Map<String, Object?> snapshot({
  double zoom = 10,
  double pitch = 0,
  int? savedAt,
}) => {
  'schema': 1,
  'savedAt': savedAt ?? DateTime.now().millisecondsSinceEpoch,
  'camera': {
    'center': [44.0, 36.0],
    'zoom': zoom,
    'bearing': 0.0,
    'pitch': pitch,
  },
  'language': 'ku',
  'mapMode': 'night',
  'sheetCollapsed': true,
  'basemapVisible': true,
  'administrativeVisible': true,
  'placesVisible': true,
  'controlsHidden': false,
};

void main() {
  late LocalState state;
  late R16Preferences preferences;
  setUp(() {
    state = LocalState(':memory:');
    preferences = R16Preferences(state);
  });
  tearDown(() => state.close());

  test('valid native camera and preferences round trip', () {
    final value = snapshot();
    preferences.save(value);
    expect(preferences.read()['snapshot'], value);
  });

  test(
    'invalid camera and future timestamps cannot replace saved preferences',
    () {
      final good = snapshot();
      preferences.save(good);
      for (final bad in [
        snapshot(zoom: -1),
        snapshot(zoom: 25),
        snapshot(pitch: 90),
        snapshot(savedAt: DateTime.now().millisecondsSinceEpoch + 120000),
      ]) {
        expect(() => preferences.save(bad), throwsA(isA<CoreFailure>()));
        expect(preferences.read()['snapshot'], good);
      }
    },
  );

  test(
    'corrupted legacy camera is discarded while tutorial completion survives',
    () {
      final imported = preferences.importLegacy({
        R16Preferences.sessionKey: jsonEncode(snapshot(pitch: 90)),
        R16Preferences.tutorialKey: '1',
        R16Preferences.trackingKey: null,
      });
      expect(imported['invalidOrExpiredSessionDiscarded'], true);
      expect(imported['snapshot'], null);
      expect(imported['tutorialCompleted'], true);
    },
  );
}
