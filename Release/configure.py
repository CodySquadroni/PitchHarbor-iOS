#!/usr/bin/env python3
"""Generate public pages and bundled contact settings from verified owner details."""
import argparse, html, json, pathlib, plistlib, re
from urllib.parse import urlparse

# Resolve paths from this script, so running it from another directory is safe.
root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument(
    "--prepare",
    action="store_true",
    help="Prepare pages and contact details before hosting; missing public URLs stay empty in the app.",
)
args = parser.parse_args()
config = json.loads((root / "Release/owner.json").read_text())
config = {key: value.strip() for key, value in config.items()}
# Validate owner details before creating any output. --prepare permits unhosted pages.
for key in ("developerName", "supportEmail") + (
    () if args.prepare else ("privacyURL", "supportURL")
):
    if not config.get(key, "").strip():
        raise SystemExit(
            f"Fill in {key} in Release/owner.json first. No pages were published."
        )
if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", config["supportEmail"]):
    raise SystemExit("Enter a valid support email.")
for key in ("privacyURL", "supportURL"):
    if args.prepare and not config.get(key):
        continue
    parsed_url = urlparse(config[key])
    if (
        parsed_url.scheme != "https"
        or not parsed_url.hostname
        or parsed_url.username
        or parsed_url.password
        or parsed_url.hostname in ("localhost", "example.com", "www.example.com")
    ):
        raise SystemExit(f"{key} must be your real, public HTTPS URL.")
# Generate HTML from templates with escaped values; this does not deploy the website.
(root / "Release/public").mkdir(parents=True, exist_ok=True)
page_values = dict(config)
page_values["privacyURL"] = config.get("privacyURL") or "privacy.html"
page_values["supportURL"] = config.get("supportURL") or "support.html"
for name in ("privacy", "support"):
    page = (root / f"Release/{name}.template.html").read_text()
    for key, value in page_values.items():
        page = page.replace("{{" + key + "}}", html.escape(value, quote=True))
    (root / f"Release/public/{name}.html").write_text(page)
# The native app reads this generated plist through ReleaseContact, without a network request.
(root / "PitchHarbor/ReleaseContact.plist").write_bytes(plistlib.dumps(config))
print(
    "Prepared Release/public/privacy.html, support.html, and bundled contact settings. Nothing was published automatically."
)
if not config.get("privacyURL") or not config.get("supportURL"):
    print(
        "Public URLs remain unset. Host the pages, add their HTTPS URLs to owner.json, run configure.py without --prepare, then rebuild."
    )
