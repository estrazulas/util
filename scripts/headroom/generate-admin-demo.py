#!/usr/bin/env python3
"""Generate an animated GIF demo of the Headroom admin interface.

Usage:
    export HEADROOM_API_KEY="hr_..."
    python scripts/generate-admin-demo.py                    # uses localhost:8787
    python scripts/generate-admin-demo.py --url https://proxy.example.com

Requires: playwright, Pillow (for ffmpeg fallback)
Run: playwright install chromium
"""

import argparse
import os
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

        # Login (not included in GIF)
        page.goto(f"{args.url}/manage/login", wait_until="networkidle")
        page.fill("input[name='api_key']", api_key)
        page.click("button[type='submit']")
        page.wait_for_timeout(2000)

        # 1 — Dashboard
        page.goto(f"{args.url}/manage", wait_until="networkidle")
        snap("01_dashboard", 2000)

        # 2 — Users
        page.goto(f"{args.url}/manage/users", wait_until="networkidle")
        snap("02_users", 2000)

        # 3 — Teams
        page.goto(f"{args.url}/manage/teams", wait_until="networkidle")
        snap("03_teams", 1500)

        # 4 — API Keys
        page.goto(f"{args.url}/manage/keys", wait_until="networkidle")
        snap("04_keys", 2000)

        # 5 — Usage overview
        page.goto(f"{args.url}/manage/usage", wait_until="networkidle")
        snap("05_usage", 2500)

        # 6 — User history combobox
        try:
            combo = page.locator("input[placeholder='Search username...']")
            combo.click()
            page.wait_for_timeout(300)
            combo.fill("admin")
            page.wait_for_timeout(800)
            snap("06_history_type", 500)
            combo.press("Enter")
            page.wait_for_timeout(400)
            load_btn = page.locator("button:has-text('Load')")
            load_btn.click()
            page.wait_for_timeout(2500)
            snap("07_history_results", 2000)
        except Exception as e:
            print(f"  [SKIP] User history: {e}")

        # 7 — Semantic search
        try:
            search_input = page.locator("input[placeholder='Search request summaries...']")
            search_input.click()
            page.wait_for_timeout(200)
            search_input.fill("error")
            page.wait_for_timeout(500)
            snap("08_search_type", 500)
            search_btn = page.locator("button:has-text('Search')")
            search_btn.click()
            page.wait_for_timeout(3000)
            snap("09_search_results", 2000)
        except Exception as e:
            print(f"  [SKIP] Semantic search: {e}")

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
