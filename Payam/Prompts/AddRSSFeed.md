# Technical Specification: Local-First RSS Engine & Minimalist UI Overhaul

## 1. The Core Objective
Replace the existing "Saved" section with a user-driven **RSS Feed Manager**. 
* **The Goal:** Move from a curated, hardcoded experience to a blank slate where the user is the architect of their own content.
* **The Constraint:** This must be **100% Local-Based**. No cloud database, no authentication, and no external API dependencies for storage. Use `localStorage` exclusively.

## 2. The "Clean Slate" Protocol
* **Hardcoded Purge:** Search the codebase and delete all static arrays, constants, or JSON objects containing pre-defined RSS subscriptions. 
* **Initial State:** On load, if the local storage is empty, the application must display an "Empty State." 
* **Abstraction:** The feature should be built so that the underlying logic (fetching/parsing) is abstracted away, leaving the UI clean and discoverable.

## 3. UI Design: The "Hero Plus" Empty State
When the user has zero subscriptions, the main workspace must transition to a minimalist "Empty State":
* **Visuals:** A single, elegant, thin-stroke **PLUS (+)** icon located in the dead center of the screen.
* **Style:** No borders, no heavy buttons. Just a clean, high-contrast (or subtle grey) "+" that feels like an invitation to create.
* **Discovery:** The sidebar should no longer say "Saved." Rename this section to "My Feeds" or "Subscribed."

## 4. The "Add Feed" Process (Step-by-Step Flow)
Clicking the central "+" (or a secondary "+" in the sidebar) must trigger a focused modal/overlay with this exact workflow:

### Step 1: Source Identification
* **Field:** A text input labeled "RSS Feed URL."
* **Validation:** Simple client-side check to ensure the input is a valid URL format.

### Step 2: Categorization (Folders)
* **The Selector:** A dropdown menu to choose an existing folder.
* **The "Add Folder" Logic:** * If the user needs a new category, provide a "＋ New Folder" option within or next to the dropdown.
    * When "New Folder" is selected, toggle an inline text input to name the new folder.
* **UI Note:** Keep this process "frictionless." The user should be able to add a URL and a new folder name in one go.

### Step 3: Local Persistence
* **Action:** Upon clicking "Subscribe," save the data object to `localStorage`.
* **Immediate Transition:** The UI must instantly switch from the "Center Plus" empty state to the "Feed View" (showing the newly added content).

## 5. Technical Data Schema
Implement the local state using a structure similar to this for future-proofing:
```json
{
  "rss_storage": {
    "folders": [
      {
        "id": "unique_folder_id",
        "name": "Design & Tech",
        "feeds": [
          { 
            "id": "feed_id", 
            "url": "[https://example.com/rss](https://example.com/rss)", 
            "title": "Example Blog" 
          }
        ]
      }
    ]
  }
}```

## 6. UI/UX Refinement
Consistency: Maintain the existing application's font, spacing, and border-radius.

The Sidebar: Display folders as collapsible headers. Under each folder, list the individual feeds with their favicons (if available) and titles.

Cleanliness: Avoid "UI clutter." Use tooltips or subtle hover states to show edit/delete options for folders.

##  7. Expected Deliverables
State Provider/Hook: A React hook (or logic block) that manages localStorage (Get, Set, Update, Delete).

Empty State Component: The centered "+" UI.

Add Feed Modal: The multi-step form for URL and Folder assignment.

Updated Sidebar: A dynamic list that renders only what is found in localStorage.

