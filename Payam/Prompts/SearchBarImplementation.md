# Task: Develop a Dynamic "Liquid Glass" Search Component

## Role
You are a Senior UI/UX Engineer and Software Architect specializing in fluid, modern interfaces and scalable MVVM architecture.

## Context
We are building a search bar for an RSS Feed application. The goal is to create a component that feels "liquid"—utilizing glassmorphism, organic transitions, and high-end aesthetic polish—while maintaining a strictly modular backend to handle evolving search requirements.

## 1. Visual & UI Specifications: "Liquid Glass" Design
Please implement the search bar with the following aesthetic principles:
* **Surface:** A semi-transparent, "frosted glass" background (Backdrop Filter: blur) with a subtle, shimmering border stroke.
* **Fluidity:** Use organic easing for the search bar expansion and result population. Elements should feel like they are floating in a liquid medium.
* **Iconography:** Update the search icon to a sleek, minimal variant that morphs or glows when active.
* **Responsiveness:** The design must adapt gracefully to different screen widths, maintaining its "glassy" depth regardless of the background content.

## 2. Technical Requirements: MVVM Architecture
* **Model:** Define a robust `RSSFeed` model (Title, Content, Metadata).
* **ViewModel:** Implement a `SearchViewModel` that manages the state of the search query and the filtered results. 
* **Search Logic (Fuzzy Matching):** * Implement a logic that matches the user's input against the **Title** of the RSS feeds.
    * Ensure the matching is "fuzzy" (handling minor typos or partial strings).
* **Extensibility Strategy:** Abstract the search criteria. I need to be able to toggle between "Title Only" and "Title + Content" (for when we add text rendering) with a single configuration change. Use a Strategy pattern or a dedicated `SearchFilter` class.

## 3. Implementation Details
* **Clean Code:** Provide well-documented code with meaningful comments.
* **Separation of Concerns:** Ensure the UI (View) knows nothing about the filtering logic; it simply observes the `FilteredList` from the ViewModel.
* **Scalability:** Structure the code so that adding "Share" functionality or "Category" filters in the future requires minimal refactoring.

## 4. Output
Please provide the complete code implementation (Logic + Styles) and a brief explanation of how to swap the search parameters from 'Title' to 'Content' later.
