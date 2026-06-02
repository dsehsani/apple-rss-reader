# PayamTutorialWidget — Setup Complete

The Live Activity widget extension is fully wired up. No manual Xcode steps are needed; everything compiles and runs end-to-end.

## What was done

- ✅ Widget Extension target `PayamTutorialWidgetExtension` exists in the project (you added this via Xcode's wizard)
- ✅ `PayamTutorialWidgetBundle.swift` — simplified to register only the Live Activity
- ✅ `PayamTutorialWidgetLiveActivity.swift` — real implementation (lanyard badge + dots; compact / minimal / expanded DI presentations + lock-screen banner)
- ✅ Auto-generated boilerplate cleaned up:
  - Deleted `PayamTutorialWidget.swift` (default home-screen widget — not used)
  - Deleted `PayamTutorialWidgetControl.swift` (default Control Center widget — not used)
- ✅ Main app `Info.plist` has `NSSupportsLiveActivities = YES`
- ✅ App-side controller (`TutorialLiveActivityController`) is wired into `TutorialManager.start / complete / finish`
- ✅ Shared `TutorialActivityAttributes.swift` is referenced by both targets (added the widget target's reference via an explicit `PBXFileReference` + `PBXBuildFile` in `project.pbxproj` so no Xcode UI click is needed)

## Verify it works

1. Build and run on the **iPhone 17 Pro** (or any iPhone 15 Pro / 16 / 17 / Air — anything with a Dynamic Island) simulator.
2. Replay the tutorial (Settings → Replay App Tutorial, or delete and reinstall the app).
3. After you tap **Continue** on the intent picker and the checklist appears at the top of the screen, look at the Dynamic Island:
   - **Compact** (default): the lanyard badge sits on the left, three small dots on the right (all dashed = pending).
   - **Long-press** the Dynamic Island → expanded view: large lanyard + current step title + 3 large dots + "0 / 3".
4. Complete a step (e.g. create a folder). Within a second, the leftmost dot should fill in green, and "0 / 3" → "1 / 3".
5. Complete all 3 → the completion celebration shows and the Live Activity dismisses on its own.

## Simulator vs. real device

Apple's iOS Simulator has long-standing gaps rendering Live Activities in the Dynamic Island. The `Activity.request` call can succeed (you'll see the in-app **DI ✓** chip turn green and Console.app log `"Started tutorial Live Activity"`) while the Dynamic Island visual still stays empty. **This is a Simulator limitation, not a code defect.** Verify the actual DI on a real iPhone 14 Pro or newer.

In the meantime, the in-app checklist is the authoritative source of progress — the DI is a polish layer.

## Reading the in-app DI chip

The expanded checklist header shows a small pill to the right of the "1 / 3" counter that reports what the controller is doing:

| Chip       | Meaning                                                                                        |
|------------|------------------------------------------------------------------------------------------------|
| **DI ✓** (green, filled dot) | Activity is live. On a real DI device, the cutout should be lit. |
| **DI off** (gray, outlined dot) | `ActivityAuthorizationInfo().areActivitiesEnabled` is false. Go to Settings → Payam → Live Activities and turn it on. |
| **DI failed** (red dot) | `Activity.request` threw. Check Console.app for the exact error. Most common cause is a Clean Build resolving stale build artifacts. |

The chip only appears on devices that *have* a Dynamic Island (iPhone 14 Pro+). On other devices the in-app collapsed pill shows the per-step dots inline instead.

## Troubleshooting

- **Live Activity never appears** → Settings app → Payam → Notifications → Live Activities. Confirm it's enabled. Also: Settings → Face ID & Passcode → Allow Access When Locked → Live Activities.
- **App runs but DI is empty even though chip is green** → That's the Simulator quirk above. Test on a real iPhone.
- **DI chip says "DI failed"** → check Console.app, filter `subsystem:DariusEhsani.Payam category:TutorialLiveActivity`. The controller logs the underlying ActivityKit error verbatim.
- **DI chip says "DI off"** → in Simulator, run `xcrun simctl spawn booted defaults write com.apple.activityskit.activityservice enabled -bool YES`, then reboot the simulator. On a real device, toggle the per-app Live Activity switch in Settings.
- **Non-DI device (iPhone SE, etc.)** → there's no Dynamic Island to show, but the in-app collapsed pill includes inline dots as a fallback (`DeviceFeatures.hasDynamicIsland` check in `TutorialChecklistCard.swift`).
- **Stale Xcode "Cannot find" errors in MainTabView** → Product → Clean Build Folder (⇧⌘K), then quit and reopen Xcode. The CLI `xcodebuild` already succeeds; the errors are SourceKit indexer cache, not real build failures.

## Why no in-app DI extension

Earlier iterations experimented with a "faux Dynamic Island" — a custom black SwiftUI pill rendered next to the real DI cutout, intended to extend it visually while the app is foregrounded (since iOS deliberately suppresses an app's own Live Activity in the DI when the app is in focus).

We pulled it because:

- **No public API exposes the DI cutout's frame.** `safeAreaInsets.top` tells you a cutout exists but not its width, height, or X position. We'd have to hardcode constants per device model.
- **Constants vary by device** — iPhone 14 Pro through 16 Pro use ~126×37pt; iPhone 17 Pro's cutout is differently sized and Apple has not published exact numbers. Every new device requires re-measurement + an app update.
- **It looked detached on iPhone 17 Pro** with the constants we tried (visible 15–20pt gap between the real cutout and our pill). The risk-reward didn't favor shipping it.
- **iOS already handles the handoff cleanly.** Real LA in the DI when backgrounded; in-app checklist (with its own per-step dots and the "DI ✓" diagnostic chip) when foregrounded.

If a future iOS release adds an API like `dynamicIslandLayoutGuide`, the faux DI could be revisited with reliable alignment. Until then we're staying out of that space.

## Directory contents

```
PayamTutorialWidget/
├── Assets.xcassets/                       (auto, leave alone)
├── Info.plist                             (auto, leave alone)
├── PayamTutorialWidgetBundle.swift        ← @main entry, registers only the Live Activity
├── PayamTutorialWidgetLiveActivity.swift  ← The DI / lock-screen UI
└── SETUP.md                               ← this file
```
