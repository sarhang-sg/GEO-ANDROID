# ڕێنمایی Termux — NAV KURD 8.0.4

بۆ بەشی Android تەنها ئەم فایلانە بخەرە ناو `Download`:

- `NAV-KURD-v8.0.4-ANDROID.zip`
- `NAV-KURD-v8.0.4-ANDROID.zip.sha256`
- `NAV-KURD-v8.0.4-ANDROID-TERMUX.sh`
- `NAV-KURD-v8.0.4-ANDROID-TERMUX.sh.sha256`

پاشان تەنها ئەم کۆدە بەکاربهێنە (بە ئەکاونتی `sarhang-sg` لە GitHub
چوونەژوورەوە بکە):

```bash
termux-setup-storage
pkg update -y
pkg install -y git gh curl unzip zip coreutils openjdk-21
gh auth login
cd /storage/emulated/0/Download
sha256sum -c NAV-KURD-v8.0.4-ANDROID.zip.sha256
sha256sum -c NAV-KURD-v8.0.4-ANDROID-TERMUX.sh.sha256
chmod +x NAV-KURD-v8.0.4-ANDROID-TERMUX.sh
bash NAV-KURD-v8.0.4-ANDROID-TERMUX.sh
```

سکریپتەکە خۆکارانە تا کۆتایی دەڕوات. ئەگەر GitHub login ـەکە
`sarhang-sg` نەبێت، بە ئاسایش دەوەستێت و هیچ شتێک upload ناکات.

## سکریپتەکە چی دەکات؟

1. ZIP و SHA-256 و source manifest دەپشکنێت.
2. `sarhang-sg/GEO-MAP` و `sarhang-sg/GEO-ANDROID` تەنها بە شێوەی Private
   دروست دەکات.
3. هیچ repo ـێکی پڕ overwrite یان force-push ناکات.
4. JKS ـی پێشوو بە fingerprint ـی ڕەسەن دەپشکنێت و چوار Actions secret ـەکە
   بە شێوەی encrypted دادەنێت.
5. GitHub Actions ـی واژۆکراو دەستپێدەکات و چاوەڕێی analyze/test/build دەکات.
6. SHA-256ی APK/AAB ـەکان و certificate ـی ڕاستەقینە دەپشکنێت.

دەرئەنجامەکان لە فۆڵدەری
`NAV-KURD-v8.0.4-RELEASE-RUN_ID` ـی `Download` دەبن.

## پاراستنی واژۆ

JKS و password لە ZIP یان Git نابن. کلیلە ڕەسەنەکە لە GitHub Actions
Secrets پارێزراوە و workflow پێش بڵاوکردنەوە fingerprint ـەکە بە
`ANDROID_APP_LINK_SHA256.txt` بەراورد دەکات. هیچ کات کلیلێکی نوێ بۆ
updateی ئەپی ئێستا دروست مەکە؛ واژۆی جیاواز ناتوانێت لەسەر ئەپی دامەزراو
update بێت.

Flutterی desktop پێویست نییە لە Termux؛ compile و signing لە GitHub Actions
ئەنجام دەدرێت.
