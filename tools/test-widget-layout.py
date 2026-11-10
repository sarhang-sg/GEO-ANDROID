import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android/app/src/main/res"
A = "{http://schemas.android.com/apk/res/android}"

class LauncherContract(unittest.TestCase):
    def test_minimum_and_resize_axes(self):
        info = ET.parse(RES / "xml/nav_kurd_widget_info.xml").getroot()
        self.assertEqual(info.get(A + "resizeMode"), "horizontal|vertical")
        for key in ("minResizeHeight", "minResizeWidth"):
            self.assertLessEqual(int(info.get(A + key).removesuffix("dp")), 48)

    def test_touch_and_accessibility_zones(self):
        for size in ("small", "dashboard"):
            root = ET.parse(RES / "layout" / f"weather_{size}.xml").getroot()
            ids = {n.get(A + "id", "").split("/")[-1]: n for n in root.iter()}
            expected = ["weather_city", "weather_forecast"]
            if size == "dashboard":
                expected += ["weather_gps", "weather_refresh"]
            for key in expected:
                self.assertTrue(ids[key].get(A + "contentDescription"))
            self.assertEqual(ids["weather_bitmap"].get(A + "scaleType"), "fitXY")

if __name__ == "__main__":
    unittest.main()
