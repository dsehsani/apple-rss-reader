---
layout: default
title: Privacy Policy — Payam
---

# Privacy Policy

**Payam** is a native iOS RSS reader developed by Darius Ehsani as a personal project.

**Effective date: May 24, 2026**

---

## 1. Who We Are

Payam is an independent iOS application. For privacy questions, contact:

**Email:** darius.ehsani@gmail.com

---

## 2. Data We Collect and Why

### 2a. Sign in with Apple

When you choose to sign in, Apple's authentication service provides:

| Data | When collected | Where stored |
|---|---|---|
| Apple User ID (opaque identifier) | First sign-in and subsequent logins | On-device (SwiftData) and your private iCloud (CloudKit) |
| Display name (given + family) | First sign-in only — Apple does not provide it again | On-device (SwiftData) and your private iCloud (CloudKit) |
| Email address or Apple private relay address | First sign-in only, **only if you choose to share it** | On-device (SwiftData) and your private iCloud (CloudKit) |

**Purpose:** Account identity and enabling iCloud sync across your own devices.

**Tracking:** None. This data is never used for advertising, analytics, or shared with third parties.

We never see this data ourselves. It is stored exclusively in your device's local SwiftData database and, if you enable iCloud sync, in your **own private CloudKit database** — a database only you can read.

---

### 2b. iCloud / CloudKit Sync

When you enable iCloud sync, Payam stores the following in your **private** iCloud CloudKit database:

- RSS feed subscriptions (URLs, titles, folder assignments)
- Folders and their names
- Saved/bookmarked articles
- Read state and preferences
- Your `UserProfile` row (Apple User ID, display name, email relay)

**Key point:** Your CloudKit private database is personal to you. Apple hosts it under your Apple ID. Darius Ehsani, as the developer, has **no ability to read, access, or export** data from your private CloudKit container. Apple's [iCloud Terms and Conditions](https://www.apple.com/legal/internet-services/icloud/) govern Apple's handling of that data.

---

### 2c. RSS and Article Fetching

When you add an RSS feed or open an article, the app makes HTTP requests to:

- The RSS feed URLs you have subscribed to
- The original article web pages (to display the full article text)

These requests are made directly from your device to those third-party servers. They receive standard HTTP request information: your IP address and an app User-Agent string. **Payam does not attach any personal identifiers to these requests.** We do not proxy, log, or store these requests on any developer-owned server.

---

### 2d. Local Article Cache

Article content is cached locally in a JSON file on your device for up to 7 days so the app can display recent articles without re-fetching them. This data never leaves your device (unless iCloud sync is enabled, in which case read/saved state is included in the sync data described in 2b).

---

### 2e. Push Notifications (Future)

The push notifications entitlement is present in the app but **not currently active.** A future update may add optional notifications for new articles. When that feature ships, this policy will be updated to describe what device-token data is collected and how it is stored. Until then, no push-notification data is collected.

---

### 2f. Cloud Services Operated by the Developer

To make the app fast and to power the in-app AI assistant, Payam contacts three back-end services that the developer operates on Amazon Web Services (AWS), in the `us-west-2` region. None of these services contains advertising, analytics, or tracking infrastructure. They exist solely to provide the features described below.

#### i. AI Assistant Service (`payam-chat`)

- **Endpoint:** `https://7qtnn7up84.execute-api.us-west-2.amazonaws.com` (`POST /v1/agent`)
- **Triggered by:** Tapping the circular assistant button on an article, or tapping "Summarize" on an article.
- **Data sent from your device:**
  - The chat messages you type in the assistant
  - The article you are currently reading: title, feed name, and the extracted plain-text body
  - A lightweight list of your subscribed feeds (title + feed URL) so the assistant can avoid recommending duplicates and can scope filter rules
  - Standard HTTP information (IP address, app User-Agent)
- **What happens on the server:** The Lambda forwards your messages and the article context to **Anthropic's Claude API** for inference and returns the model's reply to your device. Anthropic's API privacy policy governs that hop. We do not retain conversation logs beyond short-lived operational diagnostics, and we never sell, share, or use this data for training, advertising, or analytics.
- **Device identifier:** This endpoint does **not** receive the per-install device identifier described in §2f-iv.

#### ii. Server-Side Feed Polling (`payam-polling`)

- **Endpoint:** `https://h439queahl.execute-api.us-west-2.amazonaws.com` (`GET /v1/river?since=…`, `POST /v1/feeds`)
- **Triggered by:** Subscribing to or unsubscribing from a feed; opening the app to refresh the article river; background refresh.
- **Data sent from your device:**
  - The URLs of feeds you are adding or removing, and the folder names you assign
  - A timestamp (the last time your device synced) so the server only returns new items
  - The per-install device identifier described in §2f-iv (sent as the `x-payam-user` request header)
  - Standard HTTP information (IP address, app User-Agent)
- **What happens on the server:** The Lambda polls the public RSS feeds you have subscribed to, on the schedule the app sets, and returns new items to your device. The list of feeds associated with your device identifier is stored so the server knows which feeds to poll for you. We do not retain article reading state, viewing history, or analytics about which articles you opened.

#### iii. Article Extraction Cache (`payam-extract`)

- **Endpoint:** `https://kvzr90nd9a.execute-api.us-west-2.amazonaws.com` (`GET /v1/extractions/{hash}?url=…`), plus on-demand fetches of Amazon S3 presigned URLs returned by that endpoint.
- **Triggered by:** Opening an article in the in-app reader.
- **Data sent from your device:**
  - The URL of the article you opened (and a SHA-256 hash of it, used as a cache key)
  - The per-install device identifier described in §2f-iv (sent as the `x-payam-user` request header)
  - Standard HTTP information (IP address, app User-Agent)
  - Subsequent S3 presigned-URL fetches send **no** device identifier — only the IP address Amazon S3 sees as part of any HTTPS request
- **What happens on the server:** If another Payam user (or your own previous session) has already opened the same article, the Lambda returns the cleaned text and images from a shared cache, sparing your device from re-extracting it. If not, the Lambda extracts the article and stores the result in the cache for future requests.

#### iv. Per-Install Device Identifier

The first time you launch Payam, the app generates a random identifier and stores it securely in the iOS Keychain. It is sent in the `x-payam-user` HTTP header on requests to the polling and extraction services (above) to associate your subscription list and cache requests with your install. Notes:

- It is **not** an Apple ID, an advertising identifier, or any device hardware ID.
- It **is** stable across app deletions and reinstalls, because the iOS Keychain persists across uninstalls. You can clear it by erasing all content and settings on the device.
- It is **not** used for advertising, analytics, cross-app tracking, or profiling, and is never shared with third parties.
- It is **not** sent to the AI assistant service (§2f-i); that service sees only IP address and User-Agent.

---

## 3. Data We Do NOT Collect

Payam does **not** use or integrate:

- Analytics SDKs (no Amplitude, Mixpanel, Firebase Analytics, etc.)
- Crash-reporting services (no Crashlytics, Sentry, etc.)
- Advertising identifiers (no IDFA, no ATT prompt)
- Third-party tracking or data-broker services
- Third-party advertising networks of any kind

---

## 4. Your Rights and Controls

| Action | How |
|---|---|
| Stop iCloud sync | Account tab → disable "Sync with iCloud" |
| Sign out | Account tab → Sign Out (local session is cleared; local data remains on device) |
| Delete all local data | Delete the Payam app from your device |
| Delete your iCloud data | iOS Settings → \[Your Name\] → iCloud → Manage Account Storage → Payam → Delete Data |
| Reset your per-install device identifier | iOS Settings → General → Transfer or Reset iPhone → Erase All Content and Settings (full reset clears the Keychain) |
| Request information | Email darius.ehsani@gmail.com |

---

## 5. Children

Payam is not directed at children under 13. We do not knowingly collect personal information from children under 13. If you believe a child has provided personal information, contact us and we will delete it.

---

## 6. Changes to This Policy

If we make material changes, we will update the **Effective date** at the top of this page. Continued use of the app after changes are posted constitutes acceptance of the revised policy.

---

## 7. Contact

Privacy questions or requests:

**Darius Ehsani**
Email: darius.ehsani@gmail.com
