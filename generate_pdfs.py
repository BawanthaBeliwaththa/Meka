import os
import sys
from playwright.sync_api import sync_playwright

pitch_deck_html = os.path.abspath("MEKA_Pitch_Deck.html").replace("\\", "/")
brochure_html = os.path.abspath("MEKA_Product_Brochure.html").replace("\\", "/")

pitch_deck_pdf = os.path.abspath("MEKA_Pitch_Deck.pdf")
brochure_pdf = os.path.abspath("MEKA_Product_Brochure.pdf")

print("Starting PDF generation...")

with sync_playwright() as p:
    # Try Edge or default Chromium
    try:
        browser = p.chromium.launch(channel="msedge")
        print("Using Microsoft Edge for PDF generation")
    except Exception as e:
        print("Edge launch failed, falling back to default chromium:", e)
        browser = p.chromium.launch()

    # 1. Pitch Deck PDF (16:9 Landscape)
    page = browser.new_page(viewport={"width": 1920, "height": 1080})
    page.goto(f"file:///{pitch_deck_html}", wait_until="networkidle")
    page.wait_for_timeout(2000)
    page.pdf(
        path=pitch_deck_pdf,
        width="1920px",
        height="1080px",
        print_background=True,
        margin={"top": "0px", "right": "0px", "bottom": "0px", "left": "0px"}
    )
    print(f"SUCCESS: Pitch Deck PDF saved to -> {pitch_deck_pdf}")
    page.close()

    # 2. Product Brochure PDF (A4 Portrait)
    page = browser.new_page(viewport={"width": 1240, "height": 1754})
    page.goto(f"file:///{brochure_html}", wait_until="networkidle")
    page.wait_for_timeout(2000)
    page.pdf(
        path=brochure_pdf,
        format="A4",
        print_background=True,
        margin={"top": "0px", "right": "0px", "bottom": "0px", "left": "0px"}
    )
    print(f"SUCCESS: Product Brochure PDF saved to -> {brochure_pdf}")
    page.close()

    browser.close()

print("All PDFs generated successfully!")
