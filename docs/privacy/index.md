---
layout: default
title: Privacy Policy — OpenRSS
---

# Privacy Policy

**OpenRSS** is a native iOS RSS reader developed by Darius Ehsani as a personal project.

**Effective date: May 11, 2026**

---

## 1. Who We Are

OpenRSS is an independent iOS application. For privacy questions, contact:

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

When you enable iCloud sync, OpenRSS stores the following in your **private** iCloud CloudKit database:

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

These requests are made directly from your device. The servers at those URLs receive standard HTTP request information: your IP address and an app User-Agent string. **OpenRSS does not attach any personal identifiers to these requests.** We do not proxy, log, or store these requests on any developer-owned server.

---

### 2d. Local Article Cache

Article content is cached locally in a JSON file on your device for up to 7 days so the app can display recent articles without re-fetching them. This data never leaves your device (unless iCloud sync is enabled, in which case read/saved state is included in the sync data described in 2b).

---

### 2e. Push Notifications (Future)

The push notifications entitlement is present in the app but **not currently active.** A future update may add optional notifications for new articles. When that feature ships, this policy will be updated to describe what device-token data is collected and how it is stored. Until then, no push-notification data is collected.

---

## 3. Data We Do NOT Collect

OpenRSS does **not** use or integrate:

- Analytics SDKs (no Amplitude, Mixpanel, Firebase Analytics, etc.)
- Crash-reporting services (no Crashlytics, Sentry, etc.)
- Advertising identifiers (no IDFA, no ATT prompt)
- Third-party tracking or data-broker services
- Any developer-owned backend server (all data is local or in your own iCloud)

---

## 4. Your Rights and Controls

| Action | How |
|---|---|
| Stop iCloud sync | Account tab → disable "Sync with iCloud" |
| Sign out | Account tab → Sign Out (local session is cleared; local data remains on device) |
| Delete all local data | Delete the OpenRSS app from your device |
| Delete your iCloud data | iOS Settings → \[Your Name\] → iCloud → Manage Account Storage → OpenRSS → Delete Data |
| Request information | Email darius.ehsani@gmail.com |

---

## 5. Children

OpenRSS is not directed at children under 13. We do not knowingly collect personal information from children under 13. If you believe a child has provided personal information, contact us and we will delete it.

---

## 6. Changes to This Policy

If we make material changes, we will update the **Effective date** at the top of this page. Continued use of the app after changes are posted constitutes acceptance of the revised policy.

---

## 7. Contact

Privacy questions or requests:

**Darius Ehsani**
Email: darius.ehsani@gmail.com
