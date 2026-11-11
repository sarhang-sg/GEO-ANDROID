"""Recognize the visible map and handle first-launch dialogs on the test device."""
import re
import sys
import xml.etree.ElementTree as ET

try:
    root = ET.parse(sys.argv[1]).getroot()
except ET.ParseError:
    print("wait")
    sys.exit(0)

nodes = list(root.iter("node"))
labels = [(node, (node.get("text", "") + " " + node.get("content-desc", "")).strip()) for node in nodes]
skip = {"ئێستا نا", "ليس الآن", "Not now", "تێپەڕاندن", "تخطي", "Skip"}
for node, label in labels:
    if label in skip or (node.get("resource-id") == "android:id/ok" and
                         any(n.get("resource-id") == "android:id/immersive_cling_title" for n in nodes)):
        bounds = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
        if bounds:
            x1, y1, x2, y2 = map(int, bounds.groups())
            if x2 > x1 and y2 > y1:
                print("tap", (x1 + x2) // 2, (y1 + y2) // 2)
                sys.exit(0)

has_web = any(n.get("class") == "android.webkit.WebView" for n in nodes)
has_ready = any(ready in label for _, label in labels
                for ready in ("نەخشە ئامادەیە", "الخريطة جاهزة", "Map ready"))
has_loader = any("2 + 2 = 1" in label or "2 plus 2 equals 1" in label for _, label in labels)
print("ready" if has_web and has_ready and not has_loader else "wait")
