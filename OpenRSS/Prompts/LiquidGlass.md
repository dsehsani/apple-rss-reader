# SwiftUI "Liquid Glass" UI & Theme Update

**Goal:** Create a production-ready SwiftUI "Today" dashboard that implements a specific high-end "Liquid Glass" tab bar animation and a strict Light/Dark theme system.

**Context:**
I am building a premium iOS layout. I need a single-file SwiftUI prototype. 

**Visual Reference (Mental Model):**
Imagine the floating UI found in modern Apple Music or Apple News concepts.
* **The Tab Bar:** It is NOT a standard system tab bar. It is a floating capsule or bar at the bottom.
* **The "Liquid" Effect:** The active tab is highlighted by a "pill-shaped" background. When the user taps a new tab, this pill background does not just appear; it **slides and morphs** (using `matchedGeometryEffect` with a spring animation) to the new position. It should feel like a fluid sliding inside the glass bar.

**Instructions for Claude:**

Please write a complete, single-file SwiftUI solution with the following specifications:

### 1. The "Liquid Glass" Tab Bar
* **Geometry:** Create a custom bottom bar. Inside, place a background capsule behind the *currently selected* tab icon.
* **Material:** The active pill background should use a `Material.ultraThin` or a custom blur to look like frosted glass.
* **Animation:** Use `.animation(.interactiveSpring(response: 0.5, dampingFraction: 0.7), value: selectedTab)` combined with `matchedGeometryEffect`. When the tab changes, the pill must slide smoothly to the new target.
* **Separation:** As seen in high-end designs, keep the **Search** button separate if possible, or integrated on the far right as requested previously.

### 2. Header & Layout Adjustments
* **Vertical Spacing:** The "Today" header text is too low. Reduce the top padding so it sits high up, near the dynamic island/notch area.
* **Header Tools:**
    * **Filter Icon:** Place this on the left side of the tool group.
    * **Search Icon:** Place this on the **far right** side of the tool group.

### 3. Strict Color Themes (Light vs. Dark)
You must implement a rigorous color system that changes based on `@Environment(\.colorScheme)`.
* **Light Mode:** * **Background:** STRICTLY **Pure White** (`Color.white`). Do not use off-white or gray for the main background.
    * **Cards/Glass:** Use light gray or very subtle white styling with shadows to separate them from the white background.
    * **Text:** Dark/Black.
* **Dark Mode:**
    * **Background:** Deep Midnight Blue/Black (as per the original "Today" design).
    * **Cards/Glass:** Dark frosted material.
    * **Text:** White.

### 4. Code Requirements
* **Single File:** All views (Header, Cards, TabBar, Content), data models, and extensions must be in one file.
* **No Placeholders:** Include a Swift struct for the News items and an array of dummy data so the preview renders immediately.
* **Comments:** clearly mark the `// MARK: - Tab Bar Logic` section so I can see how the liquid animation works.

**Generate the full SwiftUI code now.**
