import 'core_failure.dart';

const _applicationFields = {
  'appVersion',
  'androidVersionCode',
  'releaseId',
  'releaseDate',
  'serviceWorkerRelease',
  'releaseLabel',
  'hardeningDate',
  'hardeningRelease',
};

/// Application identity changes independently of the immutable map dataset.
Map<String, Object?> validateApplicationRelease(Map<String, Object?> value) {
  if (value.isEmpty) return const {};
  if (value.keys.any((key) => !_applicationFields.contains(key)) ||
      value['appVersion'] is! String ||
      !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(value['appVersion']! as String) ||
      value['androidVersionCode'] is! int ||
      (value['androidVersionCode']! as int) < 1 ||
      value.entries.any(
        (e) => e.key != 'androidVersionCode' && e.value is! String,
      )) {
    throw const CoreFailure(
      'application_release',
      'Invalid application release identity.',
    );
  }
  return Map<String, Object?>.unmodifiable(value);
}

Map<String, dynamic> runtimeVersionInfo(
  Map<String, dynamic> dataset,
  Map<String, Object?> application,
) => Map<String, dynamic>.unmodifiable({
  ...dataset,
  ...validateApplicationRelease(application),
});
