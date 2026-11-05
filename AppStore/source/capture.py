"""Host-side capture partner for AppStoreScreenCaptureTests (Duo inner display)."""
import pathlib, subprocess, time, sys

# Run only for intentional marketing capture on the selected simulator; this enables its capture test.
DEVICE = sys.argv[1] if len(sys.argv) > 1 else "E8B0308F-59A8-4DDB-877E-B95ECE9D7CE3"
root = pathlib.Path(__file__).resolve().parents[1]
containers = (
    pathlib.Path.home()
    / f"Library/Developer/CoreSimulator/Devices/{DEVICE}/data/Containers/Data/Application"
)
runner = subprocess.check_output(
    [
        "xcrun",
        "simctl",
        "get_app_container",
        DEVICE,
        "com.app.PitchHarborUITests.xctrunner",
        "data",
    ],
    text=True,
).strip()
# Handshake: the test waits for this opt-in file, then writes a .ready marker per screen.
enabled = pathlib.Path(runner) / "tmp/PitchHarborCapture.enabled"
enabled.write_text("Marketing capture enabled")
phone = "--phone" in sys.argv
expected = 4 if phone else 8
out = root / "captures" / "iphone" if phone else root / "captures"
out.mkdir(parents=True, exist_ok=True)
seen = set()
# Bound the session so a stalled test cannot leave the host waiting indefinitely.
deadline = time.monotonic() + 240
try:
    while time.monotonic() < deadline and len(seen) < expected:
        for marker in containers.glob("*/tmp/PitchHarborCapture-*.ready"):
            name = marker.read_text().strip()
            if name in seen:
                marker.unlink()
                continue
            # Allow the UI to settle, then capture the active inner display (or standard phone display).
            time.sleep(0.7)
            subprocess.run(
                ["xcrun", "simctl", "io", DEVICE, "screenshot"]
                + ([] if phone else ["--display=3"])
                + [str(out / f"{name}.png")],
                check=True,
            )
            seen.add(name)
            marker.unlink()
            print(f"Captured {name}", flush=True)
        time.sleep(0.2)
# Always remove the opt-in marker; ordinary UI test runs must not wait for this host.
finally:
    enabled.unlink(missing_ok=True)
if len(seen) != expected:
    raise SystemExit(f"Only captured {len(seen)} of {expected} screens")
