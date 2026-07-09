#!/usr/bin/env python3
"""Generate an animated GIF demo of the Headroom admin interface.

Captures: login, users, teams, keys, usage (with history + search), roles.

Usage:
    source ~/.config/headroom/env
    python scripts/generate-admin-demo.py
    python scripts/generate-admin-demo.py --url http://localhost:8787 --api-key "hr_..."

Requires: playwright, Pillow (for ffmpeg fallback)
Run: playwright install chromium
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    sys.exit("Install playwright: pip install playwright && playwright install chromium")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://localhost:8787", help="Admin base URL")
    parser.add_argument("--api-key", help="API key (default: $HEADROOM_API_KEY)")
    parser.add_argument("--output", default="/tmp/admin-demo.gif", help="Output GIF path")
    parser.add_argument("--width", type=int, default=1280, help="Viewport width")
    parser.add_argument("--height", type=int, default=720, help="Viewport height")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    api_key = args.api_key or os.environ.get("HEADROOM_API_KEY")
    if not api_key:
        sys.exit("Provide --api-key or set HEADROOM_API_KEY")

    frames_dir = tempfile.mkdtemp(prefix="admin-demo-")

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": args.width, "height": args.height})
        frames = []

        def snap(name: str, wait_ms: int = 1500) -> str:
            page.wait_for_timeout(wait_ms)
            path = os.path.join(frames_dir, f"{len(frames):03d}_{name}.png")
            page.screenshot(path=path, full_page=False)
            frames.append(path)
            print(f"  [{len(frames):02d}] {name}")
            return path

        base = args.url.rstrip("/")

        # ── 1 — Login page (before filling) ──
        page.goto(f"{base}/manage/login", wait_until="networkidle")
        snap("01_login_empty", 1000)

        # Fill credentials and submit
        page.fill("input[name='headroomgate_key']", api_key)
        snap("02_login_filled", 600)
        page.click("button[type='submit']")
        page.wait_for_timeout(2500)

        # ── 2 — Users (redirect target of /manage) ──
        page.goto(f"{base}/manage/users", wait_until="networkidle")
        snap("03_users", 2000)

        # ── 3 — Teams ──
        page.goto(f"{base}/manage/teams", wait_until="networkidle")
        snap("04_teams", 1500)

        # ── 4 — API Keys ──
        page.goto(f"{base}/manage/keys", wait_until="networkidle")
        snap("05_keys", 2000)

        # ── 5 — Usage → User History ──
        page.goto(f"{base}/manage/usage", wait_until="networkidle")
        snap("06_usage_overview", 2500)

        # Scroll down to bring User History into view
        page.evaluate("window.scrollTo(0, 600)")
        page.wait_for_timeout(500)

        # Type into user history combobox → select "daniele"
        try:
            combo_input = page.locator("input[placeholder='Search username...']")
            combo_input.click()
            page.wait_for_timeout(300)
            combo_input.fill("daniele")
            page.wait_for_timeout(1000)
            snap("07_history_type", 500)

            # Press Enter to select first match (daniele)
            combo_input.press("Enter")
            page.wait_for_timeout(600)

            # Click Load button
            load_btn = page.locator("button:has-text('Load')")
            load_btn.click()
            page.wait_for_timeout(3000)
            snap("08_history_results", 2000)

            # Click on a session row whose summary starts with "wine"
            wine_row = page.locator("tr").filter(has=page.locator("td:last-child", has_text=re.compile(r"^wine", re.IGNORECASE))).first
            if wine_row.is_visible(timeout=3000):
                wine_row.click()
                page.wait_for_timeout(2000)
                snap("08b_history_modal", 1500)
                # Close the detail modal
                close_detail = page.locator(".fixed.inset-0.z-50 button:has-text('×')")
                if close_detail.is_visible():
                    close_detail.click()
                    page.wait_for_timeout(600)
            else:
                print("  [SKIP] No 'wine' session found, falling back to first row")
                first_row = page.locator("table tbody tr").first
                if first_row.is_visible(timeout=2000):
                    first_row.click()
                    page.wait_for_timeout(2000)
                    snap("08b_history_modal", 1500)
                    close_detail = page.locator(".fixed.inset-0.z-50 button:has-text('×')")
                    if close_detail.is_visible():
                        close_detail.click()
                        page.wait_for_timeout(600)
        except Exception as e:
            print(f"  [SKIP] User history: {e}")

        # ── 6 — Usage → Search Requests (scroll to section) ──
        try:
            # Scroll Search Requests heading into view
            search_heading = page.locator("h3:has-text('Search Requests')")
            search_heading.scroll_into_view_if_needed()
            page.wait_for_timeout(800)

            search_input = page.locator("input[placeholder='Search request summaries...']")
            search_input.click()
            page.wait_for_timeout(200)
            search_input.fill("e2e")
            page.wait_for_timeout(600)
            snap("09_search_type", 500)

            search_btn = page.locator("button:has-text('Search')")
            search_btn.click()
            page.wait_for_timeout(3000)
            snap("10_search_results", 2000)

            # Click the first search result to open detail modal
            first_result = page.locator(".space-y-3 > div.cursor-pointer").first
            if first_result.is_visible(timeout=3000):
                first_result.click()
                page.wait_for_timeout(2000)
                snap("10b_search_modal", 1500)
                # Close the detail modal
                close_detail = page.locator(".fixed.inset-0.z-50 button:has-text('×')")
                if close_detail.is_visible():
                    close_detail.click()
                    page.wait_for_timeout(600)
        except Exception as e:
            print(f"  [SKIP] Semantic search: {e}")

        # Scroll back to top for next page
        page.evaluate("window.scrollTo(0, 0)")
        page.wait_for_timeout(300)

        # ── 7 — Roles ──
        page.goto(f"{base}/manage/roles", wait_until="networkidle")
        snap("11_roles", 2000)

        # Open the provider key modal for a non-admin role
        try:
            page.wait_for_timeout(2000)
            # Wait for role cards to render (Alpine x-for renders h4 for each role)
            page.wait_for_selector("h4.font-semibold.text-lg", timeout=15000)
            page.wait_for_timeout(1000)
            # Click the "Keys" button on the first non-admin role card
            keys_btn = page.get_by_role("button", name="Keys").first
            keys_btn.wait_for(state="visible", timeout=10000)
            keys_btn.click()
            page.wait_for_timeout(2500)
            snap("12_roles_provider_keys", 2000)

            # Close the modal
            close_modal_btn = page.locator(".fixed.inset-0.z-50 button:has-text('Close')")
            if close_modal_btn.is_visible():
                close_modal_btn.click()
                page.wait_for_timeout(600)
        except Exception as e:
            print(f"  [SKIP] Roles provider modal: {e}")

        browser.close()

    # Convert to GIF via ffmpeg
    gif_path = args.output
    result = subprocess.run([
        "ffmpeg", "-y",
        "-framerate", "0.7",
        "-pattern_type", "glob",
        "-i", f"{frames_dir}/*.png",
        "-vf", "scale=960:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=256:stats_mode=diff[s0];[s1][s0]paletteuse=dither=bayer:bayer_scale=3",
        "-loop", "0",
        gif_path,
    ], capture_output=True, text=True)

    if result.returncode != 0:
        print(f"ffmpeg error: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    print(f"\nGIF saved: {gif_path} ({os.path.getsize(gif_path) // 1024} KB)")


if __name__ == "__main__":
    main()
