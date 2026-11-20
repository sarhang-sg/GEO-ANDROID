import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android/app/src/main/res"
A = "{http://schemas.android.com/apk/res/android}"


def views(layout):
    root = ET.parse(RES / "layout" / f"{layout}.xml").getroot()
    nodes = {node.get(A + "id", "").split("/")[-1]: node for node in root.iter()}
    for part in root.iter("include"):
        nodes.update(views(part.get("layout").split("/")[-1]))
    return nodes


class LauncherContract(unittest.TestCase):
    def test_minimum_and_resize_axes(self):
        info = ET.parse(RES / "xml/nav_kurd_widget_info.xml").getroot()
        self.assertEqual(info.get(A + "resizeMode"), "horizontal|vertical")
        for key in ("minResizeHeight", "minResizeWidth"):
            self.assertLessEqual(int(info.get(A + key).removesuffix("dp")), 48)

    def test_host_resize_preserves_aspect_and_has_accessible_actions(self):
        for layout in ("weather_small", "weather_dashboard"):
            with self.subTest(layout=layout):
                ids = views(layout)
                self.assertEqual(ids["weather_bitmap"].get(A + "scaleType"), "fitCenter")
                for key in ("weather_city", "weather_forecast", "weather_gps", "weather_refresh"):
                    self.assertTrue(ids[key].get(A + "contentDescription"))
                    self.assertIsNone(ids[key].get(A + "text"))
                self.assertEqual(ids["weather_pending"].get(A + "maxLines"), "1")
                self.assertEqual(ids["weather_pending"].get(A + "text"), "@string/weather_syncing")


if __name__ == "__main__":
    unittest.main()
