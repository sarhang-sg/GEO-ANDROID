#!/usr/bin/env python3
"""Protect launcher resizing, full-bleed backgrounds and weather wording."""
import json
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / 'android/app/src/main/res'
A = '{http://schemas.android.com/apk/res/android}'


def dp(value):
    return float(value.removesuffix('dp'))


class WidgetLayoutTests(unittest.TestCase):
    def test_content_fits_minimum_size_in_both_languages(self):
        for name in ('nav_kurd_widget.xml', 'nav_kurd_widget_en.xml'):
            root = ET.parse(RES / 'layout' / name).getroot()
            background = root.find('FrameLayout')
            content = background.find('LinearLayout')
            required = sum(dp(child.get(A + 'layout_height')) +
                           dp(child.get(A + 'layout_marginTop', '0dp')) +
                           dp(child.get(A + 'layout_marginBottom', '0dp'))
                           for child in content)
            required += dp(content.get(A + 'paddingTop')) + dp(content.get(A + 'paddingBottom'))
            self.assertLessEqual(required, dp(background.get(A + 'layout_height')), name)
            self.assertEqual(background.get(A + 'layout_height'), '212dp')
            self.assertEqual(background.get(A + 'layout_gravity'), 'center')
            self.assertEqual(content.get(A + 'layout_height'), 'match_parent')

    def test_one_outline_with_full_bleed_scene(self):
        for name in ('nav_kurd_widget.xml', 'nav_kurd_widget_en.xml'):
            root = ET.parse(RES / 'layout' / name).getroot()
            outlines = [e for e in root.iter() if e.get(A + 'clipToOutline') == 'true']
            self.assertEqual(len(outlines), 1)
            self.assertEqual(outlines[0].get(A + 'id'), '@android:id/background')
            scene = outlines[0].find('ImageView')
            self.assertEqual(scene.get(A + 'scaleType'), 'fitXY')
            self.assertEqual(scene.get(A + 'layout_height'), 'match_parent')
        radius = ET.parse(RES / 'values-v31/widget_dimensions.xml').getroot().find('dimen')
        self.assertEqual(radius.text, '@android:dimen/system_app_widget_background_radius')
        artwork = (ROOT / 'android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetArtwork.kt').read_text()
        scene_code = artwork.split('fun scene(', 1)[1].split('fun ', 1)[0]
        self.assertNotIn('drawRoundRect', scene_code)
        self.assertIn('canvas.drawRect', scene_code)

    def test_kurdish_cloudy_wording(self):
        codes = json.loads((ROOT / 'android/app/src/main/assets/nav_kurd_weather_descriptions.json').read_text())['codes']
        for code in ('2', '3'):
            self.assertIn('هەوراوی', json.dumps(codes[code], ensure_ascii=False))
            self.assertNotRegex(json.dumps(codes[code], ensure_ascii=False), 'هەوراو[" ]')


if __name__ == '__main__':
    unittest.main()
