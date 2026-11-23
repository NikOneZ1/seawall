#!/usr/bin/env python3
"""Write the Finder .DS_Store for the Seawall installer DMG.

Must run on macOS while the writable image is mounted, because mac_alias.Alias
reads volume attributes from the live filesystem. Called by scripts/make-dmg.sh.

  python3 scripts/dmg/write-dsstore.py /Volumes/Seawall

The window content is 640x400; icon size 128; Seawall.app at (160, 186) and
Applications at (480, 186). Keep these in sync with render-background.swift.
The Finder window is 28pt taller than the background so the title bar doesn't
crop it. WindowBounds uses QuickDraw coordinates (origin at the bottom left).
"""
from __future__ import annotations

import sys
from pathlib import Path

from ds_store import DSStore
from mac_alias import Alias

# Must match scripts/make-dmg.sh and render-background.swift.
WIN_X, WIN_Y = 200, 200
WIN_W, CONTENT_H, TITLEBAR = 640, 400, 28
WIN_H = CONTENT_H + TITLEBAR
ICON_SIZE = 128
ICON_LEFT = (160, 186)
ICON_RIGHT = (480, 186)
TEXT_SIZE = 12
BACKGROUND_NAME = ".background.tiff"


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: write-dsstore.py /Volumes/Seawall", file=sys.stderr)
        return 2
    if sys.platform != "darwin":
        print("write-dsstore.py must run on macOS (mac_alias needs the live volume).", file=sys.stderr)
        return 2

    mount = Path(argv[1]).resolve()
    background = mount / BACKGROUND_NAME
    store = mount / ".DS_Store"
    if not mount.is_dir():
        print(f"write-dsstore: mount point not found: {mount}", file=sys.stderr)
        return 1
    if not background.is_file():
        print(f"write-dsstore: missing background: {background}", file=sys.stderr)
        return 1
    if not (mount / "Seawall.app").exists() or not (mount / "Applications").exists():
        print("write-dsstore: Seawall.app and Applications must already be on the volume.", file=sys.stderr)
        return 1

    bwsp = {
        "ShowStatusBar": False,
        "WindowBounds": f"{{{{{WIN_X}, {WIN_Y}}}, {{{WIN_W}, {WIN_H}}}}}",
        "ContainerShowSidebar": False,
        "PreviewPaneVisibility": False,
        "SidebarWidth": 0,
        "ShowTabView": False,
        "ShowToolbar": False,
        "ShowPathbar": False,
        "ShowSidebar": False,
    }
    icvp = {
        "viewOptionsVersion": 1,
        "backgroundType": 2,
        "backgroundImageAlias": Alias.for_file(str(background)).to_bytes(),
        "backgroundColorRed": 1.0,
        "backgroundColorGreen": 1.0,
        "backgroundColorBlue": 1.0,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "arrangeBy": "none",
        "showIconPreview": True,
        "showItemInfo": False,
        "labelOnBottom": True,
        "textSize": float(TEXT_SIZE),
        "iconSize": float(ICON_SIZE),
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
    }

    if store.exists():
        store.unlink()
    with DSStore.open(str(store), "w+") as ds:
        ds["."]["vSrn"] = ("long", 1)
        ds["."]["bwsp"] = bwsp
        ds["."]["icvp"] = icvp
        ds["."]["icvl"] = (b"type", "icnv")
        ds["Seawall.app"]["Iloc"] = ICON_LEFT
        ds["Applications"]["Iloc"] = ICON_RIGHT

    print(f"wrote {store} (icon size {ICON_SIZE}, background {BACKGROUND_NAME})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
