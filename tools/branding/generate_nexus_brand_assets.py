#!/usr/bin/env python3
"""Generate Nexus branding assets from the canonical master SVG.

This script updates runtime/platform icon assets and UI branding files.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
MASTER_SVG = ROOT / "resources" / "branding" / "nexus_master_icon.svg"
TMP_DIR = ROOT / "build" / "branding_tmp"
PNG_PREFIX = "nexus"

DARK = "#0E223D"
WHITE = "#FFFFFF"
ACCENT = "#2FA8FF"

FAVICON_SIZES = [
    20,
    29,
    36,
    40,
    48,
    58,
    60,
    72,
    76,
    80,
    87,
    96,
    120,
    128,
    144,
    152,
    167,
    180,
    192,
    256,
    512,
    1024,
]

ANDROID_SIZES = {
    "drawable-ldpi": 36,
    "drawable-mdpi": 48,
    "drawable-hdpi": 72,
    "drawable-xhdpi": 96,
    "drawable-xxhdpi": 144,
    "drawable-xxxhdpi": 192,
}


def run(cmd: list[str]) -> None:
    resolved_cmd = cmd
    if sys.platform.startswith("win") and cmd and cmd[0].lower() == "npx":
        resolved_cmd = ["cmd", "/c", *cmd]
    print("+", " ".join(resolved_cmd))
    subprocess.run(resolved_cmd, cwd=ROOT, check=True)


def copy_file(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    print(f"copied {src} -> {dst}")


def generate_platform_icons() -> None:
    if not MASTER_SVG.exists():
        raise FileNotFoundError(f"Master SVG not found: {MASTER_SVG}")

    TMP_DIR.mkdir(parents=True, exist_ok=True)

    run(
        [
            "npx",
            "-y",
            "icon-gen",
            "-i",
            str(MASTER_SVG),
            "-o",
            str(TMP_DIR),
            "--ico",
            "--ico-name",
            "WindowsQGC",
            "--ico-sizes",
            "16,24,32,48,64,128,256",
            "--icns",
            "--icns-name",
            "macx",
            "--icns-sizes",
            "16,32,64,128,256,512,1024",
            "--favicon",
            "--favicon-name",
            PNG_PREFIX,
            "--favicon-png-sizes",
            ",".join(str(s) for s in FAVICON_SIZES),
            "--favicon-ico-sizes",
            "16,32,48",
        ]
    )

    copy_file(TMP_DIR / "WindowsQGC.ico", ROOT / "deploy" / "windows" / "WindowsQGC.ico")
    copy_file(TMP_DIR / "WindowsQGC.ico", ROOT / "resources" / "icons" / "qgroundcontrol.ico")
    copy_file(TMP_DIR / "macx.icns", ROOT / "deploy" / "macos" / "macx.icns")
    copy_file(TMP_DIR / f"{PNG_PREFIX}128.png", ROOT / "resources" / "icons" / "qgroundcontrol.png")

    for density, size in ANDROID_SIZES.items():
        copy_file(
            TMP_DIR / f"{PNG_PREFIX}{size}.png",
            ROOT / "android" / "res" / density / "icon.png",
        )

    ios_dir = ROOT / "deploy" / "ios" / "Images.xcassets" / "AppIcon.appiconset"
    for dst in sorted(ios_dir.glob("*.png")):
        with Image.open(dst) as img:
            w, h = img.size
        if w != h:
            raise ValueError(f"Expected square iOS icon: {dst} => {(w, h)}")
        src = TMP_DIR / f"{PNG_PREFIX}{w}.png"
        if not src.exists():
            raise FileNotFoundError(f"Missing generated PNG for iOS size {w}: {src}")
        copy_file(src, dst)


def _load_path_data() -> tuple[str, str, str, str]:
    ns = {"s": "http://www.w3.org/2000/svg"}
    root = ET.parse(MASTER_SVG).getroot()
    view_box = root.attrib.get("viewBox", "0 0 1024 1024")
    rect = root.find("s:rect", ns)
    group = root.find("s:g", ns)
    if rect is None or group is None:
        raise ValueError("Master SVG is missing expected <rect> or <g> nodes")

    paths = group.findall("s:path", ns)
    if len(paths) < 2:
        raise ValueError("Master SVG requires at least two paths (main + accent)")

    transform = group.attrib.get("transform", "")
    main_d = paths[0].attrib["d"]
    accent_d = paths[1].attrib["d"]
    return view_box, rect.attrib.get("rx", "228"), transform, (main_d, accent_d)


def _write_logo(path: Path, view_box: str, transform: str, main_d: str, accent_d: str, main_color: str, include_bg: bool) -> None:
    bg = f'  <rect width="1024" height="1024" rx="228" ry="228" fill="{DARK}"/>\n' if include_bg else ""
    content = (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view_box}" fill="none">\n'
        f"{bg}"
        f'  <g transform="{transform}">\n'
        f'    <path d="{main_d}" fill="{main_color}"/>\n'
        f'    <path d="{accent_d}" fill="{ACCENT}"/>\n'
        f"  </g>\n"
        f"</svg>\n"
    )
    path.write_text(content, encoding="utf-8")
    print(f"wrote {path}")


def generate_ui_logos() -> None:
    view_box, _, transform, d_values = _load_path_data()
    main_d, accent_d = d_values

    _write_logo(
        ROOT / "resources" / "QGCLogoFull.svg",
        view_box,
        transform,
        main_d,
        accent_d,
        WHITE,
        include_bg=True,
    )
    _write_logo(
        ROOT / "resources" / "QGCLogoWhite.svg",
        view_box,
        transform,
        main_d,
        accent_d,
        WHITE,
        include_bg=False,
    )
    _write_logo(
        ROOT / "resources" / "QGCLogoBlack.svg",
        view_box,
        transform,
        main_d,
        accent_d,
        DARK,
        include_bg=False,
    )


def _load_font(candidates: list[Path], size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for candidate in candidates:
        if candidate.exists():
            try:
                return ImageFont.truetype(str(candidate), size)
            except OSError:
                continue
    return ImageFont.load_default()


def generate_splash() -> None:
    splash_size = (626, 145)
    splash = Image.new("RGB", splash_size, DARK)

    icon_src = TMP_DIR / f"{PNG_PREFIX}128.png"
    icon = Image.open(icon_src).convert("RGBA")
    icon_size = 100
    icon = icon.resize((icon_size, icon_size), Image.Resampling.LANCZOS)

    icon_x = 22
    icon_y = (splash_size[1] - icon_size) // 2
    splash.paste(icon, (icon_x, icon_y), icon)

    draw = ImageDraw.Draw(splash)
    main_font = _load_font(
        [
            Path(r"C:\Windows\Fonts\segoeuib.ttf"),
            Path(r"C:\Windows\Fonts\arialbd.ttf"),
        ],
        64,
    )
    sub_font = _load_font(
        [
            Path(r"C:\Windows\Fonts\segoeui.ttf"),
            Path(r"C:\Windows\Fonts\arial.ttf"),
        ],
        20,
    )

    text_x = icon_x + icon_size + 22
    draw.text((text_x, 34), "Nexus", fill=WHITE, font=main_font)
    draw.text((text_x + 2, 96), "Wingxtra Aerospace Ltd.", fill=ACCENT, font=sub_font)

    splash_path = ROOT / "resources" / "SplashScreen.png"
    splash.save(splash_path, format="PNG")
    print(f"wrote {splash_path}")


def main() -> None:
    generate_platform_icons()
    generate_ui_logos()
    generate_splash()
    print("Nexus branding assets generated successfully.")


if __name__ == "__main__":
    main()
