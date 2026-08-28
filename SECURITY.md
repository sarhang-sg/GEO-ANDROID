# Security

- The application accepts only an HTTPS map origin.
- Android cleartext traffic is disabled.
- Geolocation and camera access are granted only to the configured NAV KURD
  origin and only after Android runtime permission.
- Unknown custom URL schemes are blocked; phone, mail, map and market links are
  delegated to Android.
- Public downloads use Android DownloadManager or scoped MediaStore storage.
- Offline WebView/IndexedDB files stay in app-private scoped storage; the app
  never requests all-files access or background location.
- Widget weather uses the last user-authorized location, caches the response
  and sends coordinates only to the HTTPS Open-Meteo forecast endpoint.
- Native diagnostics redact tokens, email addresses and precise coordinates
  before retaining a bounded local history for the feedback preview.
- Application backup and device-transfer extraction are disabled.
- WebView debugging is disabled in release builds.
- Signing keys and passwords are ignored by Git and must remain private.
- Supabase service-role credentials, Map provider secret keys and Firebase
  server credentials must never be included in this client.

Report security issues through the private owner channel or
`sarhang.salah9@gmail.com`; do not publish exploit details first.
