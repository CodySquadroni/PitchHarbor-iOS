#!/usr/bin/env python3
"""Local release checks; does not replace Xcode/App Store validation or device QA."""
import argparse, json, pathlib, plistlib, subprocess, sys
from urllib.parse import urlparse

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument(
    "--app", type=pathlib.Path, required=True, help="Path to the archived .app"
)
parser.add_argument("--require-signing", action="store_true")
args = parser.parse_args()
failures = []


# Accumulate failures so a release review sees every blocker in one run.
def check(ok, label):
    print(("PASS " if ok else "BLOCKED ") + label)
    if not ok:
        failures.append(label)


def read_plist(path):
    return plistlib.loads(path.read_bytes()) if path.exists() else {}


# Inspect the built app, not just project settings: build configurations can differ.
info = read_plist(args.app / "Info.plist")
check(info.get("CFBundleDisplayName") == "PitchHarbor", "Public app name")
check(info.get("UIDeviceFamily") == [1], "iPhone device family")
check(
    info.get("ITSAppUsesNonExemptEncryption") is False, "Exempt encryption declaration"
)
check(info.get("UILaunchStoryboardName") == "LaunchScreen", "Native launch screen")
check(
    bool(info.get("NSPhotoLibraryAddUsageDescription")),
    "Add-only Photos purpose for board image export",
)
check(info.get("MinimumOSVersion") == "18.0", "Minimum iOS version")
check(
    bool(info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon")), "Compiled app icon"
)
privacy = read_plist(args.app / "PrivacyInfo.xcprivacy")
check(
    privacy.get("NSPrivacyTracking") is False
    and privacy.get("NSPrivacyCollectedDataTypes") == [],
    "Bundled no-tracking/on-device privacy manifest",
)
check("NSAppTransportSecurity" not in info, "No App Transport Security exceptions")
# Debug fixtures must never ship. Search the actual Release executable for known markers.
executable = args.app / str(info.get("CFBundleExecutable", "missing"))
binary = executable.read_bytes() if executable.exists() else b""
check(
    bool(binary)
    and not any(
        x in binary
        for x in [
            b"--uitesting",
            b"--preview-",
            b"--app-store-capture",
            b"Northside FC",
            b"Create the Overload",
        ]
    ),
    "Release excludes demo data and test switches",
)
check(not list(args.app.rglob("*.xctest")), "No test bundles in app")
# Check bundled contacts against the owner source and require rendered public pages.
owner = json.loads((root / "Release/owner.json").read_text())
contact = read_plist(args.app / "ReleaseContact.plist")
for key in ["developerName", "supportEmail", "privacyURL", "supportURL"]:
    value = owner.get(key, "").strip()
    valid = bool(value) and contact.get(key) == value
    if key.endswith("URL"):
        parsed_url = urlparse(value)
        valid = (
            valid
            and parsed_url.scheme == "https"
            and bool(parsed_url.hostname)
            and parsed_url.hostname not in ["example.com", "localhost"]
        )
    check(valid, f"Owner setting bundled: {key}")
for name in ["privacy", "support"]:
    path = root / f"Release/public/{name}.html"
    check(
        path.exists() and "{{" not in path.read_text(),
        f"Generated public {name} page (hosting must be checked separately)",
    )
# Signing verification is optional for local unsigned archives; distribution still needs Organizer.
if args.require_signing:
    signed = (
        subprocess.run(
            ["codesign", "--verify", "--deep", "--strict", str(args.app)],
            capture_output=True,
        ).returncode
        == 0
    )
    profile = args.app / "embedded.mobileprovision"
    check(
        signed and profile.exists(),
        "Signed app with provisioning profile; also validate in Xcode Organizer",
    )
# Screenshot existence checks cannot verify visual quality or App Store approval.
check(
    bool(list((root / "AppStore/iphone-medium").glob("*.png"))),
    "Required ordinary iPhone screenshot set",
)
check(len(list((root / "AppStore/duo-inner").glob("*.png"))) == 8, "Duo screenshot set")
print(
    f"\n{len(failures)} local blocker(s). Physical testing, hosted URLs, account declarations, and App Store validation still require verification."
)
sys.exit(bool(failures))
