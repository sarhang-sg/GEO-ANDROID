# NAV KURD integration

This directory contains the complete runtime source required from the stable
`flutter_inappwebview_android` 1.1.3 package. Its unmodified pub.dev archive has
SHA-256 `62557c15a5c2db5d195cb3892aab74fcaec266d7b86d59a6f0027abd672cddba`.

NAV KURD owns two Android build changes:

- the package build uses the Android Gradle Plugin 9 public DSL, Java 17 and the
  optimized default R8 configuration;
- the malformed WebView type names in the package ProGuard rule are corrected.

The Dart API and Android runtime implementation remain the stable 1.1.3 source.
The upstream Apache-2.0 license is preserved in `LICENSE`.

The root application analyzer excludes `packages/**` from NAV KURD's
`--fatal-infos` lint gate. This vendored dependency is still resolved, compiled
and exercised by the application build and tests; only upstream package-style
notices are kept separate from first-party lint enforcement.
