#!/usr/bin/env python3
"""Automate visual-effects-prototype.html interactions and capture screenshots."""
from pathlib import Path
from playwright.sync_api import sync_playwright

BASE = Path(__file__).parent
URL = (BASE / "visual-effects-prototype.html").as_uri()
OUT = BASE / "screenshots"
OUT.mkdir(exist_ok=True)

def main():
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 393, "height": 852})
        page.goto(URL)
        page.wait_for_load_state("networkidle")

        # 1. Initial state
        page.screenshot(path=OUT / "1-initial.png")
        print("1. Screenshot: initial state (ZOOM EFFECTS dropdown + segmented bars)")

        # 2. Click ZOOM EFFECTS dropdown to open sheet
        page.click(".category-row")
        page.wait_for_timeout(400)  # wait for sheet animation
        page.screenshot(path=OUT / "2-sheet-open.png")
        print("2. Screenshot: sheet open with ZOOM EFFECTS and VISUAL EFFECTS options")

        # 3. Click VISUAL EFFECTS
        page.click("text=VISUAL EFFECTS")
        page.wait_for_timeout(300)
        page.screenshot(path=OUT / "3-visual-effects-grid.png")
        print("3. Screenshot: visual effects toggle grid (FILM GRAIN, VIGNETTE, etc.)")

        # 4. Click FILM GRAIN
        page.click("text=FILM GRAIN")
        page.wait_for_timeout(150)

        # 5. Click VIGNETTE
        page.click("text=VIGNETTE")
        page.wait_for_timeout(150)
        page.screenshot(path=OUT / "4-both-toggles-active.png")
        print("4. Screenshot: FILM GRAIN and VIGNETTE toggles active (green borders)")

        # 6. Click ZOOM EFFECTS dropdown again
        page.click(".category-row")
        page.wait_for_timeout(400)
        page.screenshot(path=OUT / "5-sheet-open-again.png")
        print("5. Screenshot: sheet open again")

        # 7. Click ZOOM EFFECTS to switch back
        page.click("text=ZOOM EFFECTS")
        page.wait_for_timeout(300)
        page.screenshot(path=OUT / "6-zoom-back-with-visual-state.png")
        print("6. Screenshot: zoom controls back, state panel shows visual effects still active")

        browser.close()

    print(f"\nScreenshots saved to {OUT}")

if __name__ == "__main__":
    main()
