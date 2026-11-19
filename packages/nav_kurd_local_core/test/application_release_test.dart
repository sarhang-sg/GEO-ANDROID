import 'package:nav_kurd_local_core/nav_kurd_local_core.dart';
import 'package:test/test.dart';

void main() {
  test('new application identity preserves immutable map provenance', () {
    final data = <String, dynamic>{
      'appVersion': '10.0.0',
      'mapDataVersion': 'verified-map-pack',
      'cacheSchemaVersion': 91,
    };
    final result = runtimeVersionInfo(data, {
      'appVersion': '11.0.0',
      'androidVersionCode': 110001,
      'androidReleaseTag': 'v11.0.0-build.110001',
    });
    expect(result['appVersion'], '11.0.0');
    expect(result['androidVersionCode'], 110001);
    expect(result['mapDataVersion'], 'verified-map-pack');
    expect(data['appVersion'], '10.0.0');
    expect(() => result['appVersion'] = 'bad', throwsUnsupportedError);
  });
  test('application release cannot override geographical identity', () {
    expect(
      () => validateApplicationRelease({
        'appVersion': '11.0.0',
        'androidVersionCode': 110001,
        'mapDataVersion': 'fake',
      }),
      throwsA(isA<CoreFailure>()),
    );
  });
  test('malformed version and code fail before opening a data worker', () {
    for (final release in [
      {'appVersion': '10.4', 'androidVersionCode': 110001},
      {'appVersion': '11.0.0', 'androidVersionCode': '110001'},
      {'appVersion': '11.0.0', 'androidVersionCode': 0},
      {
        'appVersion': '11.0.0',
        'androidVersionCode': 110001,
        'androidReleaseTag': 'v11.0.0-build.110000',
      },
    ]) {
      expect(
        () => validateApplicationRelease(release),
        throwsA(isA<CoreFailure>()),
      );
    }
  });
}
