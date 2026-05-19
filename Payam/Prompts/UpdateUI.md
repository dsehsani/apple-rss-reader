# UI Update Request (SwiftUI) — Make it feel like Apple News “liquid glass”

You’re looking at my current “Today” feed UI (dark mode). I love the overall layout, but I want these specific changes:

## 1) Top Header: Remove the “square box” behind “Today”
Right now the header area (behind “Today” + the chips) feels like a flat rectangle. I want it to feel more modern and “glass-like”.

**Change to:**
- A blurred / frosted material header (iOS-style) with **rounded corners** (or a curved capsule-like top container), not a hard rectangle.
- Subtle gradient + translucency, and it should blend into the background (no obvious box edges).
- Keep the “Today” title large and clean.

## 2) Put Search on the RIGHT, and keep Settings/Filter control near it
Currently search is on the left. I want it on the right side of the header.

**Layout target:**
- Left: “Today”
- Right: Search icon/button and the settings/filter icon (sliders) aligned together
- Make them feel like Apple-style controls (circular or rounded-rect buttons with blur material background)

## 3) Chips row stays, but polish it
The chips (Work, Productivity, Personal) should:
- Sit inside the new glass header region
- Feel like pill buttons with subtle blur/material, soft stroke, and proper spacing
- Selected state should pop, but still look native (not neon)

## 4) Bottom Tab Bar: true “Liquid Glass” like Apple News
The bottom bar currently looks flat. I want an **Apple News–style liquid glass tab bar**:
- Translucent blurred material background
- Rounded shape / floating feel
- Soft highlight + subtle border
- Icons + labels should look native and readable over blur
- Should respect safe area and feel “attached” but visually floating

## 5) Keep the feed cards as-is (mostly)
The article cards are good — don’t redesign them unless necessary for consistency with the new glass header/tab bar. If you adjust anything, keep it minimal.

---

# Implementation constraints
- SwiftUI only.
- Prefer iOS-native materials (e.g., ultraThin/regular material feel) and modern iOS styling.
- Dark mode first, but don’t break light mode.

# IMPORTANT workflow note
If you need to add **any new files** (views, modifiers, components, assets, etc.):
1) STOP and tell me exactly what file(s) you want to add  
2) Tell me the **full directory path** where you want each file created (example: `MyApp/Views/Header/GlassHeaderView.swift`)  
3) I will create the file(s), then you can continue and paste the code for me to copy in.

Proceed by:
1) Briefly describing the updated header + bottom tab bar structure you’ll implement  
2) Then providing the SwiftUI code changes
