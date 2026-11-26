# NAV KURD Android 11.0.0

Version name 11.0.0 and version code 110004 identify the application. The map presentation, Android launcher widgets and native weather activity support Kurdish, Arabic and English.

This release keeps the split Loading animation on map launch. Widget city and temperature taps open weather directly. The widget renderer reuses matching artwork or shows the saved temperature while a new size renders. The web and Android map views share the same search, contrast tokens, 3D location marker and city directory.

Build 110004 reflows the launcher widget for single-cell columns, short strips and expanded forecasts. The weather sky fills the visible launcher frame even when its reported dimensions differ. Text and weather symbols keep their proportions. Weather alerts identify the condition in the selected language. The download tag is `v11.0.0-build.110004`.

The native catalog remains independently versioned. Release automation verifies SQLite and PMTiles integrity, Flutter analysis and tests, the launcher smoke test and the Android signing certificate. Public binaries carry the established application ID and signing identity.

[Download and verification workflow](../README.md)
