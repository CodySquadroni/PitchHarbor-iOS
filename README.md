# PitchHarbor

**New to the project?** Start with the [Student Developer Guide](Docs/STUDENT-GUIDE.md) for setup, a source reading order, architecture, timing rules, and test commands.

A native, offline iOS coaching app built with SwiftUI and PencilKit. PitchHarbor brings the squad, match and tactics together under one identity. Open `PitchHarbor.xcodeproj`, select the **PitchHarbor** scheme, choose an iPhone Duo or another iPhone simulator, and run. Deployment target: iOS 18.0. No packages, API keys, account, or backend are required.

## Try it

1. On a fresh install, **Set Up PitchHarbor** guides you through Team Details, Match Defaults, Players, and Review. Enter your own team and roster, or choose **Add Players Later** to start with the practice board.
2. **Match Day → Set Up a Match**: enter an opponent, review the format and half length, confirm the rules, and choose attendance. **Edit Starting Lineup** lets you drag or tap players into positions. **Auto Pick** uses approved positions and prioritizes main positions, including the main goalkeeper. Save the lineup, create the match, then start it. For an existing ready match, use **Lineup → Auto Pick → Save Lineup** to replace older automatic assignments.
3. Record goals, pause/resume, or tap a bench player and a field player to substitute immediately. **Smart subs → Plan** sets rotation targets, approved positions and match-day readiness. Tap **Swap** on a Smart Subs suggestion when the players change. Minutes update immediately; **Undo** restores the previous players. **Undo** reverses the latest goal/substitution; **Match options → Correct score** records an explicit correction.
4. **End half** freezes minutes. Change the lineup at halftime, then **Start second half**. At full time, review individual minutes and share a report without player/team names.
5. **Practice** opens a separate tactics board. Move markers, draw with a finger or compatible Pencil, add passing arrows, opponents, cones and balls. Tap **Show players** for an edge-to-edge teaching field. Use the menu for title/notes, duplication, clearing, or PNG export.
6. **Library** finds saved boards. **Data & settings** exports/restores a versioned editable JSON backup.
7. **Match Options → Match History**: tap the trash button beside a finished game and confirm **Delete Match**. The same action is available in a finished game's options. Cancel keeps the game. Deletion removes its score, minutes, and timeline while preserving teams, boards, and other games; a failed save restores the deleted record and selection. Active games must be finished first; ready games retain **Discard Unstarted Match**.

## Layout and input

Coaching UX principle: keep attention on the game or practice. Prefer direct field interactions, visible selection, and fewer taps over opening lists or extra screens for routine changes. Tap a player to highlight them, then tap another player to swap; tapping the selected player again cancels. This now works in Edit Starting Lineup and directly on Match Day. Before kickoff, approved changes save immediately; live bench-to-field swaps apply immediately and can be undone. Practice uses the same selection pattern: tap a marker then a destination, or two markers to swap. The working product rules are recorded in `Release/COACHING-UX.txt`.

Startup uses `LaunchScreen.storyboard`, configured in both Debug and Release through `UILaunchStoryboardName`. The native launch screen shows the existing PitchHarbor icon, wordmark and tagline on forest green while iOS starts the app and the store opens its local archive. Auto Layout centers the branding inside the safe area with margins for compact phones and unfolded Duo layouts. iOS dismisses it when the app is ready: there is no artificial delay, simulated progress, or splash replay on ordinary foreground returns. Fresh installs continue into the setup wizard; existing teams open their workspace. The existing clock-recovery and saved-data error flows remain unchanged.

Launch verification: both match-day and board/team workflows pass on Duo and iPhone 16 Pro in `build/LaunchScreenVerified.xcresult` (4 runs). Debug and Release simulator builds include the compiled launch storyboard and the correct Info.plist key. `--uitesting --preview-launch` displays the actual compiled storyboard in Debug for inspection; this preview is excluded from Release. Captures: `Screenshots/duo-launch-screen.png` and `Screenshots/iphone-launch-screen.png`.

The compact score-and-clock strip and match action toolbar remain visible while content scrolls. On Duo, the field sits beside an independently scrolling Smart subs, bench and timeline panel. Available scene width controls the expanded layout, with compact Field/Players/Timeline navigation below the threshold. Accessibility text sizes use the compact layout. There are no cached physical screen dimensions or device-name layout checks. Native tab navigation adapts to the OS.

**Match day → Full screen** uses the available field area with a toolbar for start/pause/resume, goals, substitutions, end half/full time and undo. **More** opens Smart subs/bench/timeline, score correction and tactics. **Hide** directly removes the scoreboard and toolbar and expands the field; the small **Controls** button restores them. In the regular match workspace, the header's eye button hides the action toolbar while retaining the score and clock; tap its replacement to show the toolbar again. All actions use the same live match store and confirmation flows as the main workspace.

**Practice → Show players** provides an editable full-screen pitch with Move, Draw, Erase, Arrow, Add, Undo and Redo. **Hide tools** works in both the regular editor and full-screen pitch, giving the field the remaining space; **Tools** restores the toolbar and **Back** returns to the editor. Hiding tools exits drawing/arrow mode to avoid unintended marks. The field turns horizontally in landscape, keeps player numbers upright, and keeps the screen awake while presenting. Camera cutouts retain clearance. Markers, arrows and ink retain the same normalized positions through size changes.

Match and practice toolbars use ultra-thin native material and lightly tinted action backgrounds, with a solid selected/primary action. They respect Reduce Transparency and Reduce Motion. Hide/show changes only the workspace layout; the match clock, score, lineup, board contents and undo history remain in their existing stores.

Toolbar verification: `build/TranslucentToolsVerified.xcresult` passes four UI workflows on both Duo and iPhone 16 Pro (8 runs). These cover regular/full-screen hide/show, increased field area, restored score and running state, preserved board arrows, match controls, short landscape touch targets and rotation. The final system-text-color contrast adjustment also builds successfully.

Action buttons retain at least 44-point touch targets without extra bordered-button padding. Toolbars use one row at expanded widths and two or more rows on compact phones. Practice, Library and Teams use adaptive grids; substitution selection can show incoming/outgoing lists side by side when sheet width permits.

Page margins use 24 points on compact scenes and 28 on wider scenes, inside the system safe area. Practice, Teams and Library share a measured scroll layout with 20-point top and 28-point bottom spacing; grid minimums are capped at the available content width. Page headings use a consistent title size, and section headings place secondary details underneath when a single row will not fit. Match headers, score panels and controls share aligned gutters. The board editor uses an icon-only presentation action to leave space for its title, with additional clearance around its toolbar.

Spacing verification: `build/HeaderSpacingVerified.xcresult` passes six existing UI workflows on both Duo and iPhone 16 Pro (12 runs, no failures): board/team navigation, full-screen match controls, practice tools, portrait/landscape teaching mode, compact landscape match controls, and multi-position roster editing. Final simulator captures are `Screenshots/duo-header-spacing.png` and `Screenshots/iphone-header-spacing.png`.

Field objects use normalized coordinates. PencilKit uses a fixed 650 × 1000 logical canvas whose independent horizontal and vertical scales follow the available field area; ink is stored as editable PKDrawing data. Move and Draw modes have separate gesture ownership. Marker context menus provide non-drag position adjustments.

## Data and timing

`CoachStore` owns shared observable state. `Models.swift` defines value-type snapshots and participation intervals. Match records snapshot names, numbers, rules, and assignments; later team edits do not rewrite them. One unfinished match is allowed per installation.

A `ContinuousClock` anchor advances elapsed time while the process lives, including suspension; a UI timer only redraws. Every clock transition and substitution saves a checkpoint. Halftime and pause close player intervals. The second-half display starts at the configured first-half duration, while the participation ledger retains first-half added time.

After a process restart during play, the app requires explicit review of a wall-time estimate and remains paused after confirmation. It does not claim a cross-reboot monotonic anchor. Recovery is marked in the timeline.

Data is written atomically to Application Support/PitchRelay/coaching-v1.json with device file protection. Save failures remain visible. Invalid files are preserved rather than silently overwritten. Restore validates version, identifiers, lineup slots, timings and field geometry, previews counts, and requires replacement confirmation. Backups contain roster names; the match share report omits them. No analytics or networking SDKs are included.

## Smart substitutions

Match day recalculates suggestions once per second from the current lineup. Defaults are a 10-minute playing stint and a 3-minute minimum bench-rest target, adjustable for each match. Goalkeeper rotation is off by default. These are coach-set rotation preferences; the app does not estimate physical recovery or guarantee equal minutes.

- **Teams → Player details → Positions** provides a preferred-position picker and a visible, adaptive multi-select grid of additional positions with full names. Select any number of approved roles; these appear on roster and match-setup rows and carry into new matches and backups. Changing the preferred role retains the previous role as approved until explicitly deselected. In **Smart subs → Plan → player**, the same selector adjusts the current match's positions, alongside the actual on-field role and readiness. Match-only edits do not rewrite roster defaults.
- Suggestions match approved primary or alternate positions to the outgoing player's actual role. They prioritize swaps that can happen soonest, then longer stints, participation balance, primary-position fit and bench wait. Each displayed suggestion has a distinct incoming and outgoing player. Gaps in position coverage are called out.
- With a small bench, the same returning substitute is held out of a ready recommendation until their rest target is reached. A future suggestion shows the remaining wait. An unused substitute is treated as fresh. No available or position-compatible substitute produces an explanation instead of an invented swap.
- Stints count active match-clock seconds, surviving pauses. Bench rest uses a persisted timestamp and includes pauses, halftime and app closure. Negative wall-clock changes clamp rest to zero; system-clock changes can affect this reference timer. At second-half kickoff, field stints reset only when the halftime break met the configured rest target.
- Review opens with both players selected, their position, stint, rest and total playing time. Confirmation records the actual change; cancelling does nothing. A coach can manually override a rest target after seeing the remaining rest. Undo restores the prior lineup and timing origins. Confirming a swap recalculates the next suggestions.
- New optional fields preserve compatibility with existing version-1 archives. For older matches missing rotation timing, recovery or saving the plan starts new tracking; prior rest is not assumed for returning players. Backups include positions, readiness, targets and timing.

Multi-position verification: all 27 domain/persistence tests and both roster/Smart Subs UI workflows pass on Duo and iPhone 16 Pro in `build/MultiPositionFinal.xcresult` (58 runs). After compacting the preferred-position menu, both UI workflows pass again on both devices in `build/MultiPositionUIFinal.xcresult`, including changing preferred positions without losing approved cover, selecting/removing multiple roles, save/reopen, substitution review/confirm/undo and match readiness. Regression cases cover roster-to-match position transfer through a backup, alternate-role relief for the longest stint, and a midfielder returning at right back only after the rest target. Screenshots: `Screenshots/duo-player-positions.png` and `Screenshots/iphone-player-positions.png`.

Debug argument `--preview-subs` opens a disposable 14-minute sample match with substitutions and ready recommendations.

## Verification

Run the unit and UI suites with Xcode Product → Test. The suite covers match lifecycle guards, halftime, participation conservation, duplicate substitutions, score/sub undo, added-time display, roster snapshots, archive validation, restore round trips, corrupt-file preservation, running-match recovery, and UI workflows.

Example CLI (replace the destination with an installed simulator):

```sh
xcodebuild -project PitchHarbor.xcodeproj -scheme PitchHarbor \
  -destination 'platform=iOS Simulator,name=iPhone Duo' \
  -derivedDataPath build -collect-test-diagnostics never \
  -parallel-testing-enabled NO test CODE_SIGNING_ALLOWED=NO
```

Most UI tests launch with `--uitesting`, using an in-memory fictional archive so they do not modify normal coaching data. Onboarding tests use `--uitesting-setup` with a separate temporary archive; `--reset-setup-test` resets only that test archive. These switches and sample fixtures are compiled only in Debug.

## Delivery boundary

This is the blueprint's native **field-test application**, not an App Store release or completion of every V1/V2 roadmap item. Implemented: multiple teams, editable rosters, 3–11-player formats, attendance and starters, two configurable halves, running clock, goals/corrections/undo, confirmed single-pair return substitutions, position-aware smart rotation recommendations, player minutes, independent tactics, native ink, editable board library, teaching mode, PNG sharing, backups/restore, and anonymous text reports.

Still required before a broader release: physical Duo fold/unfold and supported Pencil testing; a full VoiceOver/Dynamic Type audit; historical backdated substitution correction; atomic multi-player substitution batches; limited-substitution/no-reentry rules; player season/membership migration and deletion; practice block timers; saved custom formations; season-wide minute targets; additional period formats; PDF reports; full backup migration/fault-injection testing; legal/brand/privacy/store review. Multi-coach sync, accounts, subscriptions, Live Activities and Watch support are not implemented.

An individual removed from the current roster still exists in historical match snapshots. This is roster removal, not a complete personal-data purge. Do not use this field-test build as the only copy of important match history.

## Verified in this workspace — October 22, 2026

- Debug simulator build succeeds using Xcode 27.1.
- The original 12 domain/persistence tests pass on iPhone Duo (iOS 27.1) and iPhone 16 Pro (iOS 18.3). With Smart subs, all 24 domain/persistence tests pass on Duo (`build/SmartSubsDuo.xcresult`; that bundle retains an earlier UI failure).
- Smart-sub target editing, prefilled review, cancellation, confirmation, undo, alternate positions and readiness pass on both Duo and iPhone 16 Pro in `build/SmartSubsFlowFinal.xcresult`. The match-day regression workflow also passes in `build/SmartSubsDuoUI.xcresult`. Earlier UI runs exposed an accessibility identifier issue and stale sheet inputs; both were fixed before the passing final run. A final smaller-phone layout check also passes in `build/SmartSubsPhoneVisual.xcresult`; the score stays on one line. See `Screenshots/iphone-smart-subs.png`.
- Board/team navigation, drawing, entering full-screen presentation and returning to editing pass on both simulators (`build/DuoFullFieldVerified.xcresult`, `build/iPhoneFullFieldVerified.xcresult`).
- The final camera-aware teaching layout passes portrait/landscape checks on Duo (the Duo result in `build/FullFieldSafeAreaVerified.xcresult`) and iPhone 16 Pro (`build/iPhoneFieldFinal.xcresult`). The latter used fresh derived data after an incremental test run executed a stale assertion. `Screenshots/duo-teaching.png` shows the unfolded full-screen field.
- Complete match workflow passes on both simulators after correcting full-row hit targets and disambiguating system confirmation accessibility nodes. The successful targeted reruns are `build/DuoMatchPassed.xcresult` and `build/iPhone16MatchPassed.xcresult`; earlier full-suite bundles retain the failures that led to those fixes.
- Expanded Duo match and board screenshots are in `Screenshots/`. Compact Duo launch was also visually inspected. These are simulator checks; physical fold transitions and Pencil hardware remain unverified.
- `PreviewFixtures.swift` provides compact, expanded and board previews in Xcode. Debug launch arguments `--preview-match` and `--preview-board` use disposable in-memory sample data for inspection. Combine `--preview-board --preview-teaching` to open the full-screen field directly.

### Compact Duo toolbars

- All 24 domain/persistence tests pass on both devices in `build/DuoLayoutVerified.xcresult`.
- Board/team navigation, full-screen object and arrow editing with undo/redo, hiding/restoring tools, and portrait/landscape adaptation pass on both devices in `build/DuoToolbarFinalUI.xcresult`. That bundle retains the earlier match-test failures resolved in the next run.
- Regular and full-screen match workflows pass on both devices in `build/DuoMatchToolbarVerified.xcresult`, including live scoring, manual substitutions, undo, both periods, nested rotation settings and the completed report. Native alerts confirm ending a period. Covered screens remove their controls while full-screen mode is open, avoiding duplicate accessibility elements.
- Smart-sub review and plan editing also pass in `build/DuoToolbarUI.xcresult`; that earlier bundle retains the superseded full-screen failures.
- Final one-row Duo/two-row compact-phone toolbar checks pass on both devices in `build/DuoSpacingFinal.xcresult`. The additional short-landscape iPhone test passes in `build/iPhoneLandscapeToolbar.xcresult`, checking that adjacent player hit targets do not overlap. Short landscape fields use inline name-and-number markers.
- Final screenshots: `Screenshots/duo-match-toolbar.png`, `Screenshots/duo-practice-toolbar.png`, `Screenshots/duo-workspace.png`, and `Screenshots/iphone-match-toolbar.png`.
- Debug `--preview-match --preview-full-match` opens a disposable full-screen match directly.

Layout decisions follow available scene size, consistent with [Apple’s Duo layout guidance](https://developer.apple.com/videos/play/tech-talks/111464/). No claim of physical-device certification is made.

## PitchHarbor identity

PitchHarbor is the app's public name. Its forest-green icon combines an open pitch-shaped P, player nodes and a mint passing route. The wordmark uses the app's rounded system typography; the tagline is “Your Team. Every Moment.”

The Home Screen display name, settings, welcome branding, match-report heading and exported backup/board filenames use PitchHarbor. `Brand.swift` centralizes these strings. The Xcode project, targets, module, source folders, and tests use PitchHarbor. Only the installed app bundle identifier `com.app.PitchRelay`, Application Support/PitchRelay storage directory, and version-1 backup schema retain their original identities so existing installations and saved data continue to work. No data migration or reinstall is needed for the rename.

The original name overlaps with the existing [pitchRELAY sports app](https://apps.apple.com/us/app/pitchrelay/id6806891789). A preliminary exact-name web search found no obvious PitchHarbor match; this is not confirmation of App Store, domain or trademark availability.

The generated icon master is `Branding/PitchHarbor-master.png`; its production 1024px opaque PNG is in the AppIcon asset catalog. The same artwork appears in BrandIcon for consistent in-app branding. `Branding/logo-prompt.txt` records the built-in imagegen prompt.

Brand verification: `build/PitchHarborVerified.xcresult` passes 24 domain/persistence tests plus 2 UI workflows on both Duo and iPhone 16 Pro (52 runs, no failures). The built `PitchHarbor.app` reports both CFBundleDisplayName and CFBundleName as PitchHarbor while retaining the original bundle identifier. The welcome/wordmark preview is `Screenshots/pitchharbor-welcome.png`.

## UI Copy Style

Use Title Case for app-owned headings, navigation, buttons, field labels, position names, and short status information (for example, Smart Subs and Match Day). Keep explanatory sentences in sentence case. Preserve the spelling and capitalization of user-entered names, board titles, and notes. Avoid automatic capitalization of dynamic content; Form section headers explicitly disable system all-caps styling.

Title Case verification: the four navigation, full-screen match, roster-position, and Smart Subs workflows pass on both Duo and iPhone 16 Pro across `build/TitleCaseFinal.xcresult` and `build/TitleCaseRosterVerified.xcresult`. The former retains one Duo roster-test scrolling failure; the latter passes after teaching the UI test to scroll upward to a lazy Form row. The initial interrupted `build/TitleCaseVerified.xcresult` used a stale iPhone test build and an outdated Practice-button lookup; fresh derived data and the corrected stable-ID lookup resolved those test issues. Final visual checks are in `Screenshots/duo-title-case.png` and `Screenshots/iphone-title-case.png`.

## Partially Open Duo Layouts

On iOS 27.1+, custom layouts query `GeometryProxy.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)`. They use the active division's local frame and margins plus 12 points of clearance; they do not infer a hinge position from the device name, screen midpoint, or hinge angle. A flat display or a device without an active division uses the existing layout. See [Apple's adaptive-layout guidance](https://developer.apple.com/videos/play/tech-talks/111463/).

Match Day and the practice editor, including their full-screen presentations, keep the complete field in one usable region and place score/actions, Smart Subs, or board tools in the other. Book layouts use left/right panels; tabletop layouts start with the field above the controls. Swap Sides / Swap Panels changes their docking positions with separate preferences for each axis. Narrow windows fall back to the larger usable region. Panels clip to their bounds, retain hide/show controls, and permit scrolling at larger text sizes. Board objects, arrows, ink, undo history, and match state stay in their owning models while layout changes. The roster and board-library grids widen their column gap around a vertical fold; standard sheets, alerts, and menus retain native presentation behavior.

`--preview-fold-book` and `--preview-fold-table` are Debug-only geometry fixtures, combinable with the existing disposable match/board preview flags. `--exercise-fold` adds a test-only pose switcher for state-preservation checks. These synthetic frames are never used in Release builds.

Verification: four geometry tests pass in `build/FoldLayoutChecks.xcresult` (that bundle retains the initial accessibility-container failures). Both Duo UI transition workflows pass in `build/FoldTransitionsVerified.xcresult`, covering crease clearance, swapping panels, book/tabletop/flat transitions, score and clock state, opening substitutions, board edits and undo/redo, and hide/show. Ordinary iPhone full-screen match and practice tests pass in `build/FoldPhoneRegression.xcresult`; its navigation test initially selected a horizontal scroller, corrected in the passing `build/FoldPhoneNavigationVerified.xcresult`. Earlier transition bundles retain superseded test-control failures. Physical hinge events and hardware folding have not been verified; the tests inject reserved-region geometry. The final build also removes the empty panel background when controls are hidden.

Final simulator previews: `Screenshots/duo-fold-book.png` and `Screenshots/duo-fold-tabletop.png`. The tabletop board header was compacted after visual inspection so all main tools, including Back, are visible in the shallow preview region; the final Debug build passes.

## First Launch and Release Data

Normal launches start from an empty archive: no seeded teams, players, matches, or saved boards. Fictional fixtures and their launch switches are excluded from Release. Existing version-1 archives still load unchanged and bypass setup; no saved data is deleted based on team or player names.

The four-step setup collects a team name, optional age group and season, usual players per side and half length, and an optional roster. Players support a preferred position plus multiple approved alternatives for Smart Subs. Duplicate jersey numbers and blank names cannot be saved. Coaches can review and go back before finishing; completed setup creates only their team, with no invented matches or boards. Skipping the roster offers Add Players on Match Day and leaves Practice ready to use.

Team, defaults, saved roster entries, and the current step persist locally as a draft so setup can resume after closing the app. Finish Setup opens the workspace only after a successful save. Invalid existing files remain protected, with backup restore available instead of overwriting them. Restore Backup is also available during setup. Duo uses a side-by-side introduction and form when space allows, follows active fold regions, and falls back to a single form on smaller iPhones.

Setup verification: all 37 domain/persistence tests pass on Duo and iPhone 16 Pro in `build/SetupVerified.xcresult`, including six fresh-install, draft-resume, validation, save-failure, legacy-archive, and recovery cases. That initial bundle retains a review-label UI lookup failure, corrected in `build/SetupUIFinal.xcresult`. The final polished wizard passes both end-to-end UI workflows on both devices in `build/SetupPolished.xcresult` (4 runs): saved roster with multiple positions, resume/relaunch, back/review/finish, empty library, and deferred roster with the Add Players shortcut. Debug and Release builds pass; the Release executable contains none of the checked demo identifiers or preview/test launch flags. Screenshots: `Screenshots/duo-onboarding.png` and `Screenshots/iphone-onboarding.png`.

The final visual pass uses in-card setup labels to avoid automatic all-caps section rendering on iOS 18; the redundant Team Details subheading is removed. Debug and Release builds pass after that presentation-only adjustment.

## App Store Release Audit

The release audit hardens backup validation and rollback, adds privacy/help/data deletion, improves large-text and contrast behavior, and targets iPhone/Duo. Begin with [the submission guide](Release/SUBMISSION-GUIDE.txt) and [the audit report](Release/RELEASE-REPORT.txt). Public owner/contact details and hosted privacy/support pages, final real-device TestFlight checks, and distribution signing/validation remain required. The generated unsigned archive is for inspection and has not been uploaded.

The screenshot kit now includes Duo and required ordinary-iPhone artboards. [Duo gallery](AppStore/index.html) · [iPhone gallery](AppStore/iphone.html).

## Closed Duo Layout Correction

The outer-display failure was reproduced with the screenshot preview still forcing a book division after the simulator closed. Fold preview geometry now stops dividing compact windows, while real system reserved regions remain authoritative. Each workspace fills its current geometry. Split panes require enough width for usable controls, compact screens use 16-point page gutters, the compact scoreboard puts team names above score/time, and toolbar labels drop decorative icons when they cannot fit.

On iOS 27+, navigation and editing bars explicitly remain visible while scrolling. This fixes Save/Cancel disappearing after choosing player positions on the outer display. Custom match and board toolbars retain their explicit hide/show buttons.

Closed-display regression evidence: `build/ClosedDuoLayout.xcresult` passes five geometry checks and two UI workflows on the actual Duo outer-display simulator. It checks all 11 player targets for overlap, minimum touch sizes, scoring, substitutions, board edits/undo, and hide/show. `build/CompactPhoneLayout.xcresult` passes the corresponding phone workflows, compact landscape, and largest-text controls on iPhone 16 Pro. New screenshots: `Screenshots/duo-closed-match-fixed.png` and `Screenshots/duo-closed-practice-fixed.png`. These use disposable Debug fixtures.

The compact fallback is tested in both orientations. The inner-display checks that skipped in `build/DuoAdaptiveFlows.xcresult` were rerun during the open-display follow-up below. Physical hardware testing remains outstanding.

Closed setup, Smart Subs review/confirm/undo, and privacy/settings flows now pass in `build/DuoClosedFlowsVerified.xcresult` (3 tests, no runtime warnings). The earlier `DuoAdaptiveFlows` setup failure was fixed by keeping native editing actions visible; `DuoClosedSetupFixed` retains the test-only vertical Back-button lookup corrected in the final pass. The closed-display follow-up archive is `build/PitchHarbor-1.0-Adaptive.xcarchive`; public contact/hosting and signed hardware validation remain outstanding. Refresh store captures after final layout signoff.


## Open Display and Resize Follow-Up

The running Duo initially showed an off-screen dashboard and a collapsed field. A fresh launch rendered correctly, so the follow-up targets live presentation resizing. The expanded dashboard now measures and bounds its field and scrolling sidebar within the remaining screen area; shallow windows use the compact scrolling layout. Fold panes use a custom SwiftUI Layout that allocates explicit regions instead of drawing offsets or positions. Single-region fallbacks use the same bounded placement.

Major presentation changes rebuild the content's layout identity while the owning views retain match state, tools, board edits, and undo history. Continuous resizing within a presentation does not reset identity. `--exercise-resize` is a Debug-only compact/expanded viewport test control, used together with the pose switcher; both are excluded from Release.

Verification: six geometry checks and six inner-display UI workflows pass across `build/DuoOpenLayoutsVerified.xcresult` and `build/DuoPracticeResizeVerified.xcresult`, with no skips or runtime warnings. The first bundle retains a practice-test floating-point-boundary failure; the focused final pass uses the actual window bounds with a half-point rounding tolerance. Tests cover compact/expanded resizing, portrait/landscape, book/tabletop/flat transitions, field bounds, score/running state, board editing, undo/redo, swapping, and hide/show. All four compact-phone, landscape, and largest-text workflows pass in `build/OpenLayoutPhoneRegression.xcresult`.

Visual captures: `Screenshots/duo-open-dashboard-fixed.png`, `duo-open-match-fixed.png`, `duo-book-match-fixed.png`, `duo-tabletop-practice-fixed.png`, and `duo-open-practice-fixed.png`. Book/tabletop captures and transition tests inject division regions on the real inner-display simulator; physical hinge transitions remain unverified. The initial damaged live state was captured but not reproduced by the automated resize controls. Archive: `build/PitchHarbor-1.0-OpenLayouts.xcarchive` (unsigned; supersedes Adaptive). The local release checks still have six owner/contact/hosting blockers.


## Independent Developer and Listing

Cody Squadroni is the independent developer; support is codysquadroni@gmail.com. Launch pricing is Free. The app now displays developer/contact details in Settings and its offline privacy policy. `Release/configure.py --prepare` creates personalized HTML pages and bundles contact details while permitting empty public URLs; normal `configure.py` still requires real HTTPS URLs. No page is published by that script.

The copy-ready App Store entry sheet is `AppStore/SUBMISSION-FIELDS.txt`; matching copy and structured metadata are in `store-copy.txt` and `submission-metadata.json`. `AGE-RATING-DRAFT.txt` supplies implementation-based answers for owner review, not a submitted rating. The public support/privacy pages are now hosted and linked in the app. App Store Connect submission and the remaining owner fields are still outstanding.

Current website: https://pitchharbor.netlify.app/. Support: https://pitchharbor.netlify.app/support. Privacy: https://pitchharbor.netlify.app/privacy. Netlify upload source is `Website-Netlify`; deployment details and the previous Sites deployment are preserved in `Release/SITE-DEPLOYMENT.json`. The latest unsigned archive is `build/PitchHarbor-1.0-CustomLineups-Final.xcarchive`. This does not replace signing, final hardware tests, or Apple review.


Setup keyboard follow-up (October 23, 2026): the wizard now keeps its Form at a stable structural position while allocating new frames for the keyboard, rotation, and folds. It opts out of FoldGeometryReader’s presentation identity reset; match and board behavior is unchanged. Team, age group, and season keyboard entry passes in portrait and landscape on iPhone 16 Pro and a fresh Duo simulator. The complete setup/resume flow and seven geometry tests pass. The original Duo runner stalled before launching tests; the fresh simulator results do not establish fully open hardware coverage. Re-run on the owner’s fully open Duo after installing the new build. Release archive and 19 local preflight checks pass.


Formation and jersey entry update (October 23, 2026): setup, team editing, and match setup now offer 34 formations filtered by 3v3–11v11 size, plus an optional preview. The selected shape controls new-match coordinates, default position roles used by Smart Subs, and new practice-board positions. Matches retain their own shape; old saves retain their legacy layouts. Research and the full option list are in Release/FORMATIONS-RESEARCH.txt. Both player editors use a number pad for jersey numbers, select the current value for replacement, provide Done, and block empty, invalid, or duplicate numbers. All 51 domain tests pass in FormationDomainFinal.xcresult. The initial mixed test run stalled during result finalization after a UI selector assertion; the separate final result is complete. Final setup/editing and 11v11-to-7v7 UI flows pass in FormationUIFinal.xcresult. Release archive and all 19 preflight checks pass. Physical-device validation remains required.


Guest players update (October 23, 2026): Teams now has a Guest Players section for Club Pass, Player Pass, and other guests. Queue them for the next game or add late arrivals to the active match bench. Match Setup includes guests in attendance and allows them to start; creating the match consumes the one-game queue, including absent guests, without changing the permanent roster. Match snapshots retain the pass type, positions, minutes, and rest tracking. Full Screen → More and Match Options also offer Guest Players. Before kickoff, unused bench guests can be removed; after kickoff, use Not Ready in Rotation Plan to retain the game record. Guest edits preserve timing and invalidate outdated undo snapshots. Duplicate jerseys and invalid backup data are rejected, and failed writes roll back additions, removals, and match creation.

Guest verification: all 59 domain tests pass in `build/GuestDomainVerified.xcresult`. Both team/setup and live full-screen UI workflows pass on iPhone 16 Pro in `build/GuestUI.xcresult`. A stronger alternate-position assertion found a test tap on a partially visible grid button; scrolling the button fully into view verifies selection and persistence in `build/GuestPositionsVisibleUI.xcresult`. The failed diagnostic run `GuestPositionsUI` stalled during finalization and was stopped. The unsigned release archive is `build/PitchHarbor-1.0-Guests.xcarchive`; all 19 local preflight checks pass. This feature has not yet been verified on physical Duo hardware or submitted to Apple.


Lineup follow-up (October 23, 2026): automatic selection now solves for approved formation roles across the attending squad instead of assigning roster order to field slots. Main goalkeeper takes priority over a backup; uncovered roles remain empty. The starting-lineup editor supports bench-to-field replacement, field swaps, field-to-bench moves, and a tap alternative. Drafts save explicitly; manual choices outside approved positions require confirmation. Live drops open a substitution or position-change review before changing minutes. Full-screen match mode includes a bench dock or a side rail in short landscape. Existing ready matches can be corrected with Lineup → Auto Pick → Save Lineup. All 68 domain tests and six phone UI tests pass in `build/LineupPhoneFinal.xcresult`; both new lineup UI flows pass on a clean Duo outer-display simulator in `build/LineupCleanDuo.xcresult`. The unsigned archive is `build/PitchHarbor-1.0-Lineups.xcarchive`; all 19 local preflight checks pass. Physical fully open/partially open Duo acceptance remains outstanding. QA capture: `Screenshots/duo-starting-lineup.png`.


Direct coaching follow-up (October 23, 2026): Match Day now supports two-tap field/bench swaps without entering the lineup editor. Approved pre-kickoff changes save directly; live changes use the existing confirmation and timing rules. Compact layouts put the field before Smart Subs and provide a bench strip beside the field card. Practice supports selecting a marker then tapping a spot to move, or two markers to swap, with automatic saving and Undo/Redo. Added objects are selected for quick placement. Final phone and Duo interaction checks pass, along with nine lineup domain tests and all 19 local release checks. The latest unsigned archive is `build/PitchHarbor-1.0-CustomLineups-Final.xcarchive`. See `Release/COACHING-UX.txt` for the ongoing product rules.


Midfield roles follow-up (October 23, 2026): LM and RM are now explicit player positions, separate from LW/RW. A shared Midfield Setup menu in team defaults, match setup, and the pre-kickoff lineup editor offers 4–3–3 Balanced (CM/CM/CM), Wide (LM/CM/RM), Holding (CM/DM/CM), Attacking (CM/AM/CM), and Two Attacking Mids (AM/DM/AM). DM and AM markers stagger with the role. Auto Pick and Smart Subs use the same selected slot definitions. New wide-midfield presets across team sizes use LM/RM, while old formation IDs retain their historical roles and coordinates. Saving the lineup updates the match formation atomically; cancel preserves the saved shape and team defaults remain independent. Approve LM/RM on players before expecting automatic selection in those roles. The updated archive is `build/PitchHarbor-1.0-MidfieldRoles-Final.xcarchive`, unsigned.

Midfield verification: 71 domain tests pass; phone formation setup, LM/RM roster editing, and lineup save/cancel/landscape checks pass. Final Duo closed-screen and midfield checks pass in `build/MidfieldDuoVerified.xcresult`, and all 19 local release checks pass. Short fields use compact markers to keep staggered midfield roles separate with 44-point targets. Physical open/partial-open Duo acceptance is still required.


Saved team starters and quick attendance (October 23, 2026): Teams → Starting Lineup saves a fully customizable lineup with the existing two-tap/drag field editor. Availability switches beside roster rows exclude absent players from new-match attendance without deleting their preferred starting slots. Match Setup uses available saved starters, fills gaps through approved-position matching, and keeps manual draft assignments fixed when attendance changes. Saved and manually edited slots always take priority over automatic selection, including positions outside player profiles. Automatic replacements fill only empty slots; uncovered roles stay open. Formation/size changes clear incompatible team templates, removed roster members are pruned, and old backups remain readable. Existing match snapshots stay independent.

Return to Match now lives in a dedicated tappable row above the tab container and explicitly selects the active match and Match Day tab. Returning to an already selected match preserves Undo and the running clock. The latest unsigned release archive is `build/PitchHarbor-1.0-CustomLineups-Final.xcarchive`.

Saved-lineup verification: all 78 logic tests pass. Return-to-match checks pass on phone and Duo in portrait/landscape; saved-lineup/attendance/match-creation flows pass in `build/TeamAttendancePhone.xcresult` and `build/TeamAttendanceDuoFinal.xcresult`. Existing two-tap lineup and LM/RM roster editing checks also pass. All 19 local release checks pass for the new unsigned archive. Physical-device installation and open/partial-open hardware acceptance remain outstanding.


Custom lineup correction: Save Lineup accepts any player in any position without an approval dialog. New team templates open empty; Auto Pick is an explicit option. Saved starters stay fixed at match setup, including custom roles; absence creates a vacancy rather than causing a reshuffle. Direct pre-kickoff swaps also save immediately. Automatic suggestions and Smart Subs continue to use listed positions; player profiles are not silently rewritten.

Custom lineup verification: 79 logic tests passed; the full phone custom-template → match-creation → ready-match editing flow passed in `build/CustomLineupsPhoneFinal.xcresult`. Focused team and ready-match Save/reopen checks passed on Duo in `build/CustomLineupSaveDuo.xcresult`. The broader Duo match-creation test encountered a settings-switch automation failure; its Save assertions passed, but that full flow is not counted as passing. The final unsigned archive is `build/PitchHarbor-1.0-CustomLineups-Final.xcarchive`, with all 19 local preflight checks passing.

## Coaching Consistency Update

- **Any Position** selects every supported role, including goalkeeper, while retaining the preferred role. Selecting all role chips produces the same Any Position summary. Turning it off keeps only the preferred position. Roster, guest, and match rotation editors use the same control.
- New 4–3–3 setups default to **LM / CM / RM**. On opening or restoring an archive, original three-CM team defaults and unstarted games migrate to the wide setup without changing saved players. Played games retain their original roles. Three Central Mids remains an explicit choice.
- **Teams → Edit → Position Names** provides up to 16 characters per role. Names are display aliases, validated in backups and copied into new match snapshots; canonical roles continue to drive Auto Pick and Smart Subs. Existing played match names are retained.
- The active-match banner uses explicit typed tabs and recreates the Match Day destination when returning, clearing its old navigation/presentation state while retaining the store's live clock, selected match, and Undo. It is also available while viewing history on Match Day.
- Substitution sheets and the redundant Subs button have been removed. The field's existing bench supports two taps or a drop to substitute immediately. Smart Subs offers **Swap** with the pair and role shown. Save failures roll back the action and preserve the previous Undo. Field-position moves retain their existing review.
- Permanent board, match, and team deletion uses a named destructive action, a record-specific confirmation, Cancel, and save-failure rollback. Boards have visible trash buttons in Practice and Library. Team deletion explicitly includes its roster, matches, and boards and is blocked while that team has an unfinished match. Removing a player from a roster preserves existing match snapshots. Drawing edits retain Undo.

## Project Folder Rename

Open `PitchHarbor.xcodeproj` and select the shared **PitchHarbor** scheme. Source and test folders are `PitchHarbor`, `PitchHarborTests`, and `PitchHarborUITests`. Previous build outputs, test results, temporary files, and diagnostic logs were preserved in `/Users/cody/Desktop/PitchHarbor-Previous-Builds-2026-11-05`. Historical `build/...` references above refer to that archive; fresh builds use this project’s new `build` folder.
