# SwiftUI UI Refinement Prompt

**Goal:** Refine a "Today" dashboard screen with specific layout adjustments, add a complex "Liquid Glass" animation to the tab bar, and implement full Light/Dark mode adaptability.

**Context:**
I have a SwiftUI prototype that features a glassmorphism aesthetic. It currently looks good in Dark Mode, but I need to make specific changes to the layout, animation physics, and color adaptability.

**Instructions for Claude:**

Please act as an expert iOS Engineer specializing in SwiftUI and Motion Design. I need you to write a complete, single-file SwiftUI solution that achieves the following:

### 1. Layout Adjustments (Header)
* **Vertical Positioning:** The "Today" header widget is currently too low. Reduce the top padding significantly so it sits closer to the status bar/notch area, giving the content below more breathing room.
* **Icon Arrangement:** in the top header, the icons are currently [Search] [Filter]. Please swap them. The **Search** icon must be on the **far right**, and the **Filter** icon should be to the **left of the search icon**.

### 2. "Liquid Glass" Bottom Tab Bar
* Implement a custom Tab Bar that replaces the standard system tab bar.
* **The Effect:** Create a "Liquid Glass" interaction. When the user taps a different tab, the active background indicator (a "pill" shape) should not just fade in/out. It should slide to the new position.
* **Animation Physics:** Use a spring animation (e.g., `.interpolatingSpring` or `.spring(response: 0.5, dampingFraction: 0.7)`) to make the pill feel organic and fluid as it moves. It should feel like it stretches slightly and snaps into place.
* **Visuals:** The moving pill should have a glassmorphism style (Blur material + slight opacity) that looks premium.

### 3. Light & Dark Mode Support
* The current design is hardcoded for Dark Mode.
* Refactor the colors to be adaptive.
* **Light Mode:** The background should be a soft off-white/light gray, text should be dark, and the glass effects should use a lighter frosted material (e.g., `Material.ultraThin` with a white tint).
* **Dark Mode:** Keep the existing deep blue/black aesthetic with dark frosted glass.
* Use `@Environment(\.colorScheme)` or standard semantic colors (e.g., `Color(uiColor: .systemBackground)`) so it toggles automatically.

### 4. Code Constraints
* **Single File:** Do not ask me to create multiple files or extensions. Put all necessary views, extensions, and data models into one single, copy-pasteable code block.
* **Clarity:** Comment the code heavily so my developers understand exactly where the "Liquid" animation logic lives and how the theme switching works.
* **Mock Data:** Include a small amount of dummy data for the news cards so the preview compiles and runs immediately.

**Generate the full SwiftUI code now.**
