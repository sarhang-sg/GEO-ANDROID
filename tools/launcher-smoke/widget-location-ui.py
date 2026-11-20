"""Exercise the published app through Flutter, the city picker and the launcher."""
from pathlib import Path
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

out=Path(sys.argv[1])
def adb(*args, timeout=12):
    return subprocess.check_output(['adb',*args],timeout=timeout,stderr=subprocess.DEVNULL)
def tree():
    try:
        adb('shell','uiautomator','dump','/sdcard/nav-weather.xml',timeout=9)
        return ET.fromstring(adb('shell','cat','/sdcard/nav-weather.xml'))
    except (OSError,subprocess.SubprocessError,ET.ParseError):
        return ET.Element('empty')
def label(n):
    return (n.get('content-desc') or n.get('text') or '').strip()
def find(word,*,prefix=False,scroll=False,timeout=38):
    until=time.monotonic()+timeout
    rows=[]
    while time.monotonic()<until:
        rows=list(tree().iter('node'))
        matches=[n for n in rows if (label(n).startswith(word) if prefix else label(n)==word)]
        matches.sort(key=lambda n:(n.get('clickable')!='true',len(label(n))))
        for n in matches:
            bounds=list(map(int,re.findall(r'-?\d+',n.get('bounds',''))))
            if len(bounds)==4 and bounds[2]>bounds[0] and bounds[3]>bounds[1]:
                return (bounds[0]+bounds[2])//2,(bounds[1]+bounds[3])//2
        if scroll:
            adb('shell','input','swipe',str(width//2),str(height//4),str(width//2),str(height*4//5),'240')
        time.sleep(.45)
    raise AssertionError(f'Missing {word!r}. Visible labels: {[label(n)[:65] for n in rows if label(n)][:22]}')
def tap(word,**opts):
    x,y=find(word,**opts);adb('shell','input','tap',str(x),str(y));time.sleep(.5)
def capture(file):
    (out/file).write_bytes(adb('exec-out','screencap','-p'))
def open_settings():
    tap('شوێنی ویجێت',scroll=True)
    find('خۆکار بە GPS',prefix=True)
def pinned(expected):
    find('شوێنی دیاریکراو · '+expected,prefix=True)
def select_pin():
    tap('ئەم شوێنە بۆ ویجێت دابنێ',prefix=True)
width,height=map(int,re.findall(r'(\d+)x(\d+)',adb('shell','wm','size').decode())[-1])
adb('shell','pm','grant','com.navkurd.app','android.permission.ACCESS_COARSE_LOCATION')
adb('shell','pm','grant','com.navkurd.app','android.permission.ACCESS_FINE_LOCATION')
adb('shell','cmd','location','set-location-enabled','false')
open_settings()
select_pin()
open_settings()
pinned('هەولێر')
adb('shell','input','keyevent','4')
tap('هەولێر',scroll=True)
tap('دڵخوازەکان · سلێمانی',prefix=True)
tap('سلێمانی',prefix=True)
open_settings()
pinned('هەولێر')
capture('viewing-other-city-with-pinned-widget.png')
select_pin()
open_settings()
pinned('سلێمانی')
capture('pinned-sulaymaniyah.png')
tap('خۆکار بە GPS',prefix=True)
open_settings()
nodes=list(tree().iter('node'))
assert any(label(n).startswith('خۆکار بە GPS') for n in nodes)
assert not any('شوێنی دیاریکراو' in label(n) for n in nodes)
capture('automatic-gps.png')
adb('shell','input','keyevent','4')
adb('shell','cmd','location','set-location-enabled','true')
print('PASS signed APK UI: pin Erbil, star and view Sulaymaniyah, retain Erbil, pin Sulaymaniyah, reset to automatic GPS')
