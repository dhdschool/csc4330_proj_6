"""Renders assets/logo/logo.svg to the PNGs the app uses.

Uses Playwright with Microsoft Edge (already installed for the backend). From
the frontend folder, after editing logo.svg:

    ../backend/.venv/Scripts/python tool/render_logo.py
    dart run flutter_launcher_icons
"""
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

logo_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent.parent / "assets" / "logo"
svg = (logo_dir / "logo.svg").read_text(encoding="utf-8")

# (file, background, scale, hide): Android crops icons to a circle, so its
# foreground is just the calendar page, enlarged, without the square tile and
# corner stars; the lavender comes from adaptive_icon_background.
outputs = [
    ("logo.png", "transparent", 1.0, ""),
    ("app_icon.png", "#FFFFFF", 1.0, ""),
    ("app_icon_foreground.png", "transparent", 1.3, ".tile, .stars"),
]

with sync_playwright() as p:
    browser = p.chromium.launch(channel="msedge")
    page = browser.new_page(viewport={"width": 1024, "height": 1024})
    for name, background, scale, hide in outputs:
        size = 1024 * scale
        page.set_content(
            f"""<html><body style="margin:0;width:1024px;height:1024px;
            background:{background};display:flex;align-items:center;justify-content:center;overflow:hidden">
            <style>{hide} {{ display: none; }}</style>
            <div style="width:{size}px;height:{size}px;flex-shrink:0">{svg.replace('width="1024" height="1024"', 'width="100%" height="100%"')}</div>
            </body></html>"""
        )
        page.screenshot(path=str(logo_dir / name), omit_background=background == "transparent")
        print("wrote", name)
    browser.close()
