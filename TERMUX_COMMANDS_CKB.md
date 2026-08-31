# ڕێنمایی Termux — NAV KURD 9.0.0

وەشانی کۆتایی Web 9.0.0 پێشتر تاقیکراوەتەوە و بڵاوکراوەتەوە. سکریپتی
Android ئەو دۆخە دەپشکنێت و هیچ UI یان runtime ـێکی Web overwrite ناکات.
بۆ بەشی Android ئەم فایلانە لە `Download` دابنێ:

- `NAV-KURD-v9.0.0-ANDROID.zip`
- `NAV-KURD-v9.0.0-ANDROID.zip.sha256`
- `NAV-KURD-v9.0.0-ANDROID-TERMUX.sh`
- `NAV-KURD-v9.0.0-ANDROID-TERMUX.sh.sha256`

پاشان تەنها ئەم کۆدە بەکاربهێنە (بە ئەکاونتی `sarhang-sg` لە GitHub
چوونەژوورەوە بکە):

```bash
termux-setup-storage
pkg update -y
pkg install -y git gh curl unzip zip coreutils openjdk-21 nodejs-lts
gh auth login
cd /storage/emulated/0/Download
sha256sum -c NAV-KURD-v9.0.0-ANDROID.zip.sha256
sha256sum -c NAV-KURD-v9.0.0-ANDROID-TERMUX.sh.sha256
chmod +x NAV-KURD-v9.0.0-ANDROID-TERMUX.sh
bash NAV-KURD-v9.0.0-ANDROID-TERMUX.sh
```

سکریپتەکە خۆکارانە تا کۆتایی دەڕوات. ئەگەر GitHub login ـەکە
`sarhang-sg` نەبێت، بە ئاسایش دەوەستێت و هیچ شتێک upload ناکات.

## سکریپتەکە چی دەکات؟

1. ZIP و SHA-256 و manifest ـی پاککراوەی Android دەپشکنێت.
2. `sarhang-sg/GEO-ANDROID` بە شێوەی Private دروست دەکات یان branch ـێکی
   review لە repo ـە تایبەتەکەدا بەکاردهێنێت؛ repo ـی Web ـیش private دەپشکنێت.
3. هیچ repo ـێکی پڕ overwrite یان force-push ناکات.
4. JKS ـی پێشوو بە fingerprint ـی ڕەسەن دەپشکنێت و چوار Actions secret ـەکە
   بە شێوەی encrypted دادەنێت.
5. GitHub Actions ـی واژۆکراو دەستپێدەکات و چاوەڕێی analyze/test/build دەکات.
6. SHA-256ی APK/AAB ـەکان و certificate ـی ڕاستەقینە دەپشکنێت.
7. تەنها هەمان APK ـی پشتڕاستکراو و metadata ـی download/release دەخاتە
   branch ـێکی Web؛ هیچ UI یان runtime ـێک ناگۆڕێت.
8. چاوەڕێی quality و Chromium smoke دەکات و تەنها لە سەرکەوتندا merge دەکات.

دەرئەنجامەکان لە فۆڵدەری
`GEO-ANDROID-V9-RELEASE-RUN_ID` ـی `Download` دەبن.

## پاراستنی واژۆ

JKS و password لە ZIP یان Git نابن. کلیلە ڕەسەنەکە لە GitHub Actions
Secrets پارێزراوە و workflow پێش بڵاوکردنەوە fingerprint ـەکە بە
`ANDROID_APP_LINK_SHA256.txt` بەراورد دەکات. هیچ کات کلیلێکی نوێ بۆ
updateی ئەپی ئێستا دروست مەکە؛ واژۆی جیاواز ناتوانێت لەسەر ئەپی دامەزراو
update بێت.

Flutterی desktop پێویست نییە لە Termux؛ compile و signing لە GitHub Actions
ئەنجام دەدرێت.
