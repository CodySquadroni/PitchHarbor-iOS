PITCHHARBOR — APP STORE SCREENSHOT COLLECTION

Deliverables
• duo-inner/: eight finished, opaque PNGs, 2853 × 2007 pixels each.
• index.html: local collection preview. Open in a browser; select an image for full resolution.
• collection-preview.png: contact sheet for reviewing the set together.
• captures/: untouched simulator source images, including an alternate teaching view.
• source/: editable HTML/CSS, copy in slides.json, logo, renderer, and capture script.
• store-copy.txt: suggested English (US) listing copy.
• manifest.json: output dimensions, source mapping, and captions.

Upload Order
01 Match Day
02 Smart Subs
03 Full-Screen Field
04 Practice Whiteboard
05 Players & Positions
06 Your Playbook
07 Simple Setup
08 Adaptive Duo Layout

Use the eight PNGs in duo-inner for the iPhone Duo INNER DISPLAY slot. The contact sheet, gallery, and raw captures are review/source material, not additional uploads. These are English (US), landscape assets. A separate required ordinary-iPhone set is in iphone-medium/. A Duo outer-display set is not included.

Apple specifies 2853 × 2007 landscape (or 2007 × 2853 portrait) for the Duo inner display, JPEG or PNG, with no alpha/transparency. Specifications checked October 22, 2026:
https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications

Artwork
Forest green, mint, warm white, rounded typography, and subtle field geometry follow the PitchHarbor identity. The UI images are actual simulator captures. The outline is a presentation frame, not an Apple hardware render. Captured UI is not redrawn or retouched. Layouts preserve its aspect ratio.

Example Data and Layout Provenance
The example team, player names, score, and saved boards are disposable Debug fixtures. They never write to the normal coaching archive and are excluded from Release. Normal installs start empty with setup.

Screens 01–07 use the standard expanded layout via the Debug-only --preview-flat window-layout fixture; native system sheets retain the simulator’s own presentation behavior. Screen 08 captures the running app’s divided layout using the Debug-only --preview-fold-book geometry fixture, with --preview-full-match. This supplies a deterministic division to the same layout implementation used by native reserved regions. This is a simulator illustration, not physical-device certification or a photograph of folded hardware.

Regenerate Artwork
From the repository root: node AppStore/source/render.cjs
Requires Node, Playwright, Sharp, and local Chrome. Set PITCHHARBOR_NODE_MODULES to the directory containing those modules and PITCHHARBOR_CHROME to the Chrome executable if the defaults do not match your machine. Rendering is local; no external fonts or services are needed.

Refresh Captures
The capture test skips during ordinary test runs. Install the test runner once with Xcode testing if needed. Start python3 AppStore/source/capture.py <Duo simulator UUID>, then run the AppStoreScreenCaptureTests target test on that simulator. The host script captures display 3 while a temporary-file handshake holds each screen steady. XCUIScreenshot currently targets an inactive Duo display, so it is deliberately not used. The host script only touches its own capture-handshake files in the test runner’s temporary directory.

Current capture results: build/ReleaseDuoScreensFinal.xcresult and build/ReleasePhoneScreensFinal.xcresult. Older capture result: build/AppStoreFlatCapture.xcresult. The original split-pane capture result is build/AppStoreCaptureFinal.xcresult. The earlier build/AppStoreCapture.xcresult contains a superseded scrolling failure and inactive-display screenshots; none of those images are used in the final artwork.

The renderer checks capture dimensions, headline overflow, output dimensions, and alpha. All finished images were visually reviewed. No App Store upload or submission has been performed.

Release verification: the Release simulator build succeeds and its executable contains none of the checked marketing fixture names or capture-only flags. build/AppStoreCaptureOptIn.xcresult verifies the capture test skips when its helper is not running.

ORDINARY IPHONE SET
The release audit adds iphone-medium/ (four opaque 1206 × 2622 portrait PNGs). Upload these to the iPhone with Dynamic Island medium display slot, alongside the Duo inner-display set. Source images are actual iPhone 16 Pro simulator screens in captures/iphone/. Run source/render-phone.cjs to rebuild the artboards. The screenshots use disposable Debug fixtures; Release contains no seeded team.

Phone refresh: run source/capture.py with the iPhone simulator UUID and --phone while explicitly running AppStoreScreenCaptureTests/testCapturePhoneFeatures. Use source/render-phone.cjs afterward. Never run capture fixtures against a coach's live data.

OWNER AND LISTING UPDATE — OCTOBER 23, 2026
Developer: Cody Squadroni (individual). Support: codysquadroni@gmail.com. Launch price: Free.
SUBMISSION-FIELDS.txt is the primary entry sheet; store-copy.txt and submission-metadata.json contain synchronized listing values. AGE-RATING-DRAFT.txt contains prepared questionnaire answers for final review. Nothing has been entered in App Store Connect in this task.
The screenshot artwork and older App Store Kit ZIP predate the latest layout and listing changes. Refresh the artwork before submission. Release/PitchHarbor-Submission-Info.zip contains the updated text/page package only.

The public Support URL and Privacy Policy URL are now in SUBMISSION-FIELDS.txt and submission-metadata.json. Both pages are live without a login. No separate domain purchase is needed.
