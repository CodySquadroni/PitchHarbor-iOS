# Welcome to PitchHarbor

PitchHarbor is a native, offline soccer coaching app built with SwiftUI and PencilKit. It keeps team rosters, match time, scores, substitutions, and practice boards on the device. There is no app account, backend, analytics SDK, or external Swift package dependency.

The product principle is **fewer taps, eyes on the game**. Routine coaching actions should happen directly on the field, with clear selection and quick recovery from mistakes. Read `Release/COACHING-UX.txt` before proposing a new interaction.

## First Session

1. Open `PitchHarbor.xcodeproj` and select the **PitchHarbor** scheme.
2. Use the project's current Xcode/SDK toolchain. The deployment target is iOS 18.0, but the source also references newer fold-layout APIs behind availability checks; an older SDK may not compile those symbols.
3. Choose an iPhone simulator and Run. A normal fresh launch opens the team wizard with no fictional roster.
4. Create a disposable team, add players with preferred and alternate positions, save a team starting lineup, and create a match. Try a two-tap bench/field swap, Undo, pause, and halftime.
5. Create a practice board. Move a marker, draw, change orientation, hide/show tools, and try Undo/Redo. Notice that the match lineup stays unchanged.
6. Export an editable backup through Data & Settings. Use a disposable simulator for restore/erase experiments.
7. Run the logic tests before making changes, then follow the reading order below.

For a populated **Debug** simulator session, add `--uitesting --preview-match --preview-flat` in Scheme → Run → Arguments. This uses an in-memory sample store rather than the normal archive. Remove those arguments to test real first-run and persistence behavior. The fixture switches and sample records are excluded from Release.

## Suggested Reading Order

| Read | What to learn |
| --- | --- |
| `PitchHarbor/PitchHarborApp.swift` | One store is created at the app entry point, injected into the view environment, and checkpointed on scene lifecycle changes. |
| `PitchHarbor/Models.swift` | Persisted value types, roster vs. match snapshots, slot assignments, and playing-time arithmetic. |
| `PitchHarbor/CoachStore.swift` | Commands, validation, clock ownership, persistence, failure handling, recovery, and match Undo. |
| `PitchHarbor/LineupPlanner.swift` and `SmartSubs.swift` | Pure calculation code: automatic lineup matching and rotation advice. |
| `PitchHarbor/OnboardingViews.swift` and `ContentView.swift` | Startup routing, tab navigation, match presentation, and actions forwarded into the store. |
| `PitchHarbor/TeamViews.swift` and `LineupEditor.swift` | Draft editing, attendance reconciliation, and saved team starters. |
| `PitchHarbor/FoldLayout.swift` and `DesignSystem.swift` | Geometry, reusable controls, accessibility, and responsive field rendering. |
| `PitchHarbor/BoardViews.swift` | Independent practice editing, normalized coordinates, PencilKit, autosave, and Undo/Redo. |
| The matching files in `PitchHarborTests` | Executable examples of intended behavior and edge cases. |

`// MARK:` comments organize large files in Xcode's jump bar. File comments explain responsibility; `///` comments describe types and contracts; inline comments explain decisions that are easy to accidentally break. Comments should explain **why**, rather than repeat every visible Swift statement.

## Architecture and State Ownership

```text
PitchHarborApp
  └─ CoachStore (@MainActor, @Observable)
       ├─ AppArchive → teams, matches, boards, setup draft, selected IDs
       ├─ transient clock anchor, recovery flags, save error, one-event Undo
       └─ protected local JSON file

StartupView
  ├─ blocked storage → recovery/settings
  ├─ no teams → TeamSetupWizard
  └─ ContentView → Match Day / Practice / Teams / Library

Screen action → store command → model/planner calculation → save attempt
                       ↓
                observed UI updates
```

- **Persisted values:** `Player`, `Team`, `Match`, `Board`, and `AppArchive` are structs conforming to `Codable`. A copy is a snapshot, not a live reference to another struct.
- **Shared mutable state:** `CoachStore` owns the archive. `@MainActor` serializes its commands on the UI actor; `@Observable` lets SwiftUI refresh views reading changed properties.
- **Screen state:** `@State` holds drafts, selection, sheet visibility, toolbar visibility, and board Undo history. A `@Binding` lets a child edit state owned by its parent.
- **Environment:** views obtain the shared store with `@Environment(CoachStore.self)`. A separate environment value supplies position-name aliases.
- **Pure calculations:** formation geometry, lineup assignment, and Smart Subs can be tested without tapping the UI. Keep decision rules there rather than duplicating them in view branches.

Team, player, lineup, and rotation forms work with drafts. Cancel normally discards that draft. The first-run wizard deliberately saves progress, and the practice board deliberately autosaves edits. Read the specific screen's contract before assuming all forms behave alike.

## Models and Saved Data

| Type | Ownership and invariant |
| --- | --- |
| `Player` | Permanent profile with a preferred canonical role, approved alternatives, and availability. Any Position includes every supported role, including GK. |
| `Team` | Roster, defaults, optional custom position labels, saved starting lineup, and pending one-game guests. |
| `SavedStartingLineup` | Dictionary of formation slot index → player UUID. It is tied to a specific format and formation ID. |
| `MatchPlayer` | Independent player snapshot plus field slot, played intervals, stint origin, bench-rest origin, readiness, and optional guest type. |
| `Match` | Team/opponent labels, roster snapshot, formation, phase, scores, timing, rotation policy, and timeline. |
| `Board` | Team-associated practice document containing normalized markers/arrows, notes, and PencilKit drawing bytes. |
| `AppArchive` | Versioned root JSON document. At most one unfinished match may exist across all teams. |

**Never use array order as a player identity.** UUIDs identify people/records; slot indices identify formation positions. A bench player's slot is `nil`. A saved match's roster must not change when a team profile is edited or removed.

Canonical roles such as `CM`, `LM`, and `GK` drive matching. `PositionNames` contains optional display aliases, such as “CDM” for `DM`. Aliases are copied into new matches and must not replace the canonical keys.

The app's public name, module, scheme, and executable are PitchHarbor. Two legacy strings are intentional compatibility contracts:

- Installed bundle identifier: `com.app.PitchRelay`.
- Local archive: `Application Support/PitchRelay/coaching-v1.json`, inside the app container.

Changing them casually can disconnect an update from the installed app or existing coaching data. The desktop folder name does not determine the on-device archive location.

### Validation and Persistence

`CoachStore.validate` checks more than successful JSON decoding: supported versions, references, unique IDs and jersey numbers, slot bounds, finite/bounded timing, formation compatibility, and drawing payloads. Views rely on those invariants when indexing formation arrays.

`readBackup` reads in bounded chunks with a 50 MB limit. Restore validates before replacing data and is blocked during an unfinished game. Corrupt startup data blocks writes so it is preserved for recovery. On-disk writes use atomic replacement and iOS Data Protection. Exported JSON is editable and contains names; it is not password encrypted.

Many commands snapshot the previous archive and roll back if saving fails, including direct substitutions, lineup saves, and destructive deletions. **Not every command is transactional:** `editMatch` and `saveBoard`, for example, can leave unsaved in-memory changes and expose `saveError`. Do not infer successful persistence just because the screen changed. Preserve error feedback and check the return contract when adding commands. A store with `fileURL: nil` skips disk writes and validation inside `save()`; persistence tests must use temporary files or call validation explicitly.

New optional Codable fields keep old backups readable. Required fields, raw enum values, formation IDs, and renamed Codable properties need an explicit compatibility plan and round-trip/legacy tests.

## Follow a Coaching Action Through the Code

### Starting Lineup

1. Teams → Starting Lineup opens `LineupEditor` with a local dictionary of assignments.
2. Taps and drops converge on `LineupPlanner.placing`. Two field players swap; a bench player replaces the occupant. Dragging to the bench removes a starter.
3. Save calls the parent's callback. A team template may be empty; a match needs at least one starter. Manual positions can differ from a player's approved profile.
4. `MatchSetupView` starts with available saved starters. `fillingVacancies` keeps those slots fixed and fills only gaps through approved positions.
5. Creating the match copies eligible players and labels into a new snapshot. Pending guests are consumed for that game, not added to the permanent roster.

`automatic` uses a small dynamic-programming search. An integer bitmask tracks occupied slots; at most 11 slots means at most 2,048 occupancy states. Each player is considered once. The score first favors filling slots, then preferred saved assignments, then main positions, with extra priority for a main goalkeeper. Unsupported slots stay empty. Fixed manual assignments are retained even if reshuffling could fill more positions.

Formation roles and field points must stay in the same order. New 4–3–3 defaults use LM/CM/RM; explicit variants and legacy IDs remain readable. The targeted migration updates team defaults and ready matches, not played history.

### Live Substitution and Undo

1. `LivePitch` and bench controls forward tap/drop intent to `MatchWorkspace`.
2. `tapMatchPlayer` and `dropPlayer` choose the action from the current phase and destination.
3. Before kickoff, custom placements save directly. During play, bench-to-occupied-slot swaps call `CoachStore.substitute` immediately. Field-position changes and vacant-slot arrivals retain review.
4. The model settles outgoing minutes, transfers slot/role, starts the incoming interval when running, and updates stint/rest origins.
5. The store saves, or rolls back on failure. After success it retains one Undo snapshot. Undo restores players/score and marks the event voided; it does not rewind the clock.

Smart Subs only recommends. Its candidate pairs must cover the outgoing canonical role and exclude bench players marked Not Ready. It ranks by due time, stint, participation balance, preferred role, rest, and a stable pair tie-breaker, then avoids reusing players across recommendations. Goalkeeper rotation is opt-in. A never-used substitute is treated as fresh; returning players need known rest tracking. This is rotation guidance, not an estimate of physical recovery.

### Clock Example

The code intentionally uses two time domains:

| Quantity | Clock | Pause behavior |
| --- | --- | --- |
| Match elapsed and player minutes | Active match time, advanced by `ContinuousClock` | Stops while paused or at halftime |
| Current field stint | Active match time since `stintStartedAt` | Preserved across pauses |
| Bench rest | Wall time since `benchedAt` (`Date`) | Continues during pauses and halftime |
| Relaunch estimate | Saved active time plus time since the saved wall anchor | Requires coach review; resumes in paused state |

Example: a player enters at active time 120 seconds and leaves at 420 seconds, earning 300 seconds. A pause between those points adds no minutes. A benched player's rest still increases during that pause. At second-half kickoff, field stints reset only if halftime reached the configured rest target.

`closeIntervals` settles totals and clears open entry origins. `openIntervals` starts new active intervals. Displayed half time uses `periodStart`; first-half added time does not incorrectly shift second-half display time. Keep timing logic in these shared methods, not a view timer. `TimelineView` refreshes presentation; it does not own match time.

## Layout and Input

`FoldPaneLayout` reads the window's system division region where supported, computes usable rectangles with clearance, and falls back to the largest region if two panes would be too small. A flat/closed window uses ordinary adaptive geometry. Avoid hardcoding a device name or assuming every wide view has a crease.

`FoldGeometryReader` can recreate presentation identity when the layout category changes. Durable state must stay above that boundary. `TeamSetupWizard` disables that identity refresh and keeps its form in the same structural position while only its rectangle changes; otherwise a keyboard resize can dismiss the first responder. Do not “simplify” this into separate copies of the form for each layout.

`DesignSystem` centralizes gutters, colors, compact buttons, selected-player treatment, the pitch, and translucent toolbars. Preserve 44-point touch targets even when the visible icon is small. Check large Dynamic Type, dark/light appearance, Reduce Transparency, VoiceOver labels, and orientation changes when changing shared components. Accessibility identifiers are also UI-test contracts.

The active-match banner clears stale navigation/presentation state and selects the Match Day tab while preserving the store. Simply changing the tab is insufficient if an old sheet or history destination is still active.

## Practice Board and PencilKit

Markers and arrows use normalized coordinates. Ink uses a fixed **650 × 1000** canvas. `StableInkView` scales the canvas to the available viewport; it does not repeatedly rewrite the strokes when the phone rotates or folds.

`InkCanvas` bridges SwiftUI bindings and `PKCanvasViewDelegate`. Its coordinator uses `lastData` and `applying` to avoid treating a programmatic Undo/restore as a fresh user edit. Drawing, moving, and arrows have separate gesture ownership so an invisible ink layer does not swallow marker taps.

`BoardEditor.remember` snapshots the board before an edit and caps Undo at 50 snapshots. A new edit clears Redo. These snapshots include ink and are separate from match Undo. Autosave calls `saveBoard`; errors surface through the store. Image export renders a board preview, writes a protected temporary PNG, presents the system share sheet, and removes the temporary share file when the sharing presentation is dismissed.

## Remaining File Map

| File or folder | Purpose |
| --- | --- |
| `Brand.swift` | Product text, export filenames, reusable logo lockup. |
| `SetupControls.swift` | Shared formation/midfield pickers and numeric jersey editing. |
| `GuestPlayerViews.swift` | Explicit destination for pending or live-match guests; validates jersey collisions. |
| `SmartSubsViews.swift` | Suggestions, match-only rotation drafts, and shared player position controls. |
| `SettingsView.swift` | Backup file picker/exporter and restore/erase confirmations. |
| `PrivacyAndHelpViews.swift` | Bundled contact reader and offline policy/coaching help. |
| `PreviewFixtures.swift` | In-memory Debug fixtures for screenshots, previews, and UI tests. |
| `LaunchScreenPreview.swift` | Debug inspection of the real launch storyboard. |
| `LaunchScreen.storyboard`, `Assets.xcassets` | Native startup layout, icons, and artwork; edit with the appropriate Xcode editors. |
| `PrivacyInfo.xcprivacy`, `ReleaseContact.plist` | Privacy declarations and generated owner contact settings. |
| `PitchHarbor.xcodeproj` | Build targets/settings and shared scheme. Folder-synchronized source groups pick up Swift files; use Xcode when changing membership/settings. |
| `Release/owner.json` | Developer contact and hosted support/privacy URLs. |
| `Release/configure.py` | Escapes owner values into HTML templates and writes the bundled contact plist. Generates locally; does not publish. |
| `Release/preflight.py` | Inspects a built `.app` for local release requirements. Not an App Store approval guarantee. |
| `Release/*.template.html` | Editable source for generated public contact/policy pages. |
| `Release/public`, `Release/site/dist` | Generated/prepared web artifacts; avoid treating output edits as source changes. |
| `Website-Netlify` | Manually hostable site: `index.html`, local screenshot assets, `styles.css`, `site.js`, support/privacy pages, and hosting configuration. |
| `AppStore/source` | `render.cjs` uses `slides.json` and `artboards.css`; `render-phone.cjs` owns the phone template. Both generate artboard HTML, PNGs, galleries, and manifests from existing captures. `capture.py` coordinates new simulator captures. |
| `AppStore/captures`, screenshot PNG folders | Captured input images and prepared marketing exports; regenerate deliberately. |
| `build` | Disposable local build/test/archive outputs; not source or onboarding material. |

The Netlify upload folder is maintained separately from `Release/public`; regenerating release contacts does not rebuild or publish the entire marketing site. Keep public privacy/support copy aligned across the native app, templates, and hosted files. Current published URLs are stored in `Release/owner.json`.

The website's `site.js` only switches screenshots and controls the native image dialog, including focus restoration. It has no app-data connection. Styles and HTML comments identify major page areas. Keep page IDs and `data-view` keys consistent with the JavaScript map.

## Tests and Commands

Use **Product → Test** (⌘U) in Xcode, or run from the project directory. Select an installed simulator in place of `SIMULATOR_ID`; list IDs with `xcrun simctl list devices available`.

```sh
xcodebuild -project PitchHarbor.xcodeproj -scheme PitchHarbor \
  -destination 'platform=iOS Simulator,id=SIMULATOR_ID' \
  -derivedDataPath build/DerivedData \
  -only-testing:PitchHarborTests test CODE_SIGNING_ALLOWED=NO
```

The logic suites use **Swift Testing** (`@Test`, `#expect`, `#require`); UI workflows use **XCTest** (`XCUIApplication`, `XCTAssert...`). Tests touching the store run on the main actor. In-memory fixtures are convenient, but use unique temporary files for persistence, invalid archives, and failed-save scenarios. Pass explicit elapsed/wall times to pure logic rather than sleeping to simulate minutes.

| Suite | Behavior protected |
| --- | --- |
| `PitchHarborTests` | Core match lifecycle, timing, Undo, recovery, backup, snapshot independence. |
| `LineupTests`, `TeamLineupTests` | Correct positions, saved/custom starters, attendance, stale targets, rollback. |
| `SmartSubsTests` | Approved roles, rest/stints, keeper opt-in, timing compatibility, plan isolation. |
| `FormationTests` | Shape counts, role/point order, legacy IDs, midfield variants, jersey parsing. |
| `GuestPlayerTests` | One-game guests, late arrival, destination validation, minute preservation. |
| `OnboardingTests` | Empty startup, resumable draft, completion validation, corrupt-file recovery. |
| `MatchHistoryTests`, `CoachingConsistencyTests` | Safe deletion, aliases, Any Position, migration, direct swaps. |
| `FoldLayoutTests` | Fold clearance, fallback regions, setup focus-related geometry. |
| `ReleaseSafetyTests` | Oversized/malformed imports, rollback, erase/discard restrictions. |
| `PitchHarborUITests` | Actual setup, field, board, roster, navigation, accessibility, resize/fold workflows. |
| `AppStoreScreenCaptureTests` | Opt-in capture flows; skipped unless the host capture helper enables them. |

A useful small UI smoke selection is:

```sh
xcodebuild -project PitchHarbor.xcodeproj -scheme PitchHarbor \
  -destination 'platform=iOS Simulator,id=SIMULATOR_ID' \
  -derivedDataPath build/DerivedData -parallel-testing-enabled NO \
  -only-testing:PitchHarborUITests/PitchHarborUITests/testQuickLiveFieldSubstitution \
  -only-testing:PitchHarborUITests/PitchHarborUITests/testPracticeTapMoveSwapAndUndo \
  -only-testing:PitchHarborUITests/PitchHarborUITests/testSetupKeyboardInPortrait \
  test CODE_SIGNING_ALLOWED=NO
```

Do not run the screenshot capture helper as an ordinary test: it writes an opt-in marker into the selected test runner and waits for a companion capture test. Read `AppStore/README.txt` and the comments in `AppStoreScreenCaptureTests.swift` first. Debug fold/resize previews exercise layout branches; physical closed, partially open, and fully open device checks still matter for layout changes.

The repository's `.swift-format` specifies four-space indentation and a 120-column target. Use the formatter bundled with the project toolchain:

```sh
xcrun swift-format format --in-place --recursive PitchHarbor PitchHarborTests PitchHarborUITests
xcrun swift-format lint --recursive PitchHarbor PitchHarborTests PitchHarborUITests
```

Prefer one statement per line even if the formatter preserves semicolons. Keep comments close to the invariant they describe. Avoid restyling unrelated files in a functional change.

Local unsigned release verification:

```sh
xcodebuild -project PitchHarbor.xcodeproj -scheme PitchHarbor \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/PitchHarbor-Local.xcarchive archive CODE_SIGNING_ALLOWED=NO
python3 Release/preflight.py \
  --app build/PitchHarbor-Local.xcarchive/Products/Applications/PitchHarbor.app
```

An unsigned archive is a build check, not a distributable App Store upload. Release instructions and owner declarations live under `Release`. Use a fresh archive/result path when retaining earlier verification results.

## Making a First Change

A good first task is a small help-text correction or a narrowly scoped improvement to a shared label. Trace where it appears, make the change, and verify that screen at compact and expanded sizes. For deeper work:

- **Add a persisted field:** choose compatibility defaults, update archive validation, and test old-backup decode plus new-backup round trip.
- **Add a formation:** define a stable ID and aligned roles/points; add count/geometry tests and check the shared picker. Do not reinterpret an existing played-match ID.
- **Adjust Smart Subs:** change the pure rules and deterministic tests first; keep coach intent explicit and preserve the two time domains.
- **Change a live action:** identify its allowed phases, stale-selection guards, save-failure behavior, and Undo contract before touching the UI.
- **Change a layout:** keep state above geometry branches, preserve keyboard identity, and test orientation/fold transitions during an edit or match.

Before handing off a change, describe the behavior changed, the reason, the checks run, and any limits. Keep commits focused when working in version control. Do not add sample teams to production startup, silently rewrite match history, or turn routine player swaps into extra dialogs. Maintain the app's coaching principle as you learn its implementation.
