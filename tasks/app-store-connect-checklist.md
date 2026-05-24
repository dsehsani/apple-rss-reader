# App Store Connect Submission Checklist — Payam

## Step 1: Enable GitHub Pages (one-time)

1. Go to https://github.com/dsehsani/apple-rss-reader/settings/pages
2. Under **Build and deployment**, set **Source** to **Deploy from a branch**
3. Set **Branch** to `main`, folder to `/docs`
4. Click **Save**
5. Wait 1–5 minutes, then verify in a private/incognito browser (on cellular, not Wi-Fi):
   `https://dsehsani.github.io/apple-rss-reader/privacy/`
   — it must return HTTP 200 with the policy text, no login wall, no redirect.

---

## Step 2: App Store Connect — App Information

**Location:** App Store Connect → Your App → App Information (sidebar)

| Field | Value |
|---|---|
| **Privacy Policy URL** | `https://dsehsani.github.io/apple-rss-reader/privacy/` |

Paste this URL and save **before** you submit the build for review.

---

## Step 3: App Privacy Questionnaire

**Location:** App Store Connect → Your App → App Privacy (sidebar)

Work through each data-type category. Use the answers below.

### Contact Info

- **Email Address** — **Yes, we collect this**
  - Is it linked to the user's identity? **Yes**
  - Is it used to track the user? **No**
  - Purpose: **App Functionality** (account authentication / iCloud sync)

### Identifiers

- **User ID** — **Yes, we collect this** (the opaque Apple User ID)
  - Is it linked to the user's identity? **Yes**
  - Is it used to track the user? **No**
  - Purpose: **App Functionality** (account authentication / iCloud sync)

- **Device ID** — **Yes, we collect this** (per-install random UUID stored in iOS Keychain, sent as `x-payam-user` header to the polling and extraction Lambdas)
  - Is it linked to the user's identity? **Yes**
  - Is it used to track the user? **No**
  - Purpose: **App Functionality** (associate subscription list with install; cache coordination)

### User Content

- **Other User Content** — **Yes, we collect this**
  - **What's collected:**
    - RSS feed subscriptions, folders, bookmarks, reading state stored in the user's private CloudKit database
    - Chat messages and currently-reading article context sent to the developer-owned AI assistant Lambda (powered by Anthropic's Claude)
    - Feed URLs sent to the developer-owned polling Lambda for server-side RSS fetching
  - Is it linked to the user's identity? **Yes**
  - Is it used to track the user? **No**
  - Purpose: **App Functionality** (sync across devices; AI assistant; server-side polling)

### Browsing History

- **Browsing History** — **Yes, we collect this** (article URLs sent to the developer-owned extraction-cache Lambda when an article is opened, used as the cache key)
  - Is it linked to the user's identity? **Yes**
  - Is it used to track the user? **No**
  - Purpose: **App Functionality** (cross-device cache of extracted article content)

### All Other Categories

Answer **No** for every other category:
- Health & Fitness: No
- Financial Info: No
- Location: No
- Sensitive Info: No
- Contacts: No
- Search History: No
- Usage Data: No
- Diagnostics: No
- Purchases: No
- Other Data: No

### Tracking

- **Does this app use data to track users?** — **No**

---

## Step 4: Sign in with Apple Declaration

**Location:** App Store Connect → Your App → App Review Information (or Features)

When prompted about authentication methods, confirm Sign in with Apple is your sole authentication mechanism.

---

## Step 5: Final Sanity Checks Before Clicking Submit

- [ ] Privacy Policy URL resolves to a non-empty HTML page on cellular data
- [ ] No HTTP → HTTPS redirect (URL must be HTTPS directly)
- [ ] Page is not behind a login or paywall
- [ ] Policy mentions Sign in with Apple and iCloud sync specifically
- [ ] Policy mentions all three developer-owned Lambdas (chat, polling, extract) by name and what data flows to each
- [ ] Policy has a contact email address
- [ ] Policy has an effective date
- [ ] In-app Settings → "About" section shows the Privacy Policy link
- [ ] Account screen shows "By signing in you agree to our Privacy Policy" under the Sign in with Apple button

---

## Step 6: Beta App Review Information

**Location:** App Store Connect → Your App → TestFlight → Beta App Review Information

Required before testers can install the first build.

### Contact Information

| Field | Value |
|---|---|
| First Name | `Darius` |
| Last Name | `Ehsani` |
| Phone Number | *<fill in>* |
| Email | `darius.ehsani@gmail.com` |

### Demo Account

Check **"Sign-in not required"**. In the notes field paste:

> App uses Sign in with Apple. Reviewer may sign in with any Apple ID, or tap "Continue as Guest" on the onboarding screen to use the app without an account.

### Notes for the Beta Review Team

> Payam is a personal RSS reader with optional iCloud sync (private CloudKit database) and an in-app AI assistant. The assistant is powered by Anthropic's Claude via the developer's own AWS Lambda (us-west-2); it accepts the currently-reading article text and chat messages and returns suggestions/summaries. To test the chat: open any article → tap the circular logo in the bottom-right → send a message. To test the article summary action: open any article ≥50 words → tap "Summarize". No backend account or login is required for any of these features.

### What to Test (paste into the build's "What to Test" field for each upload)

> Build 1 — first TestFlight cut.
>
> Please verify:
> • Onboarding flow and Sign in with Apple
> • Adding/removing RSS feeds and folders (try The Verge, NPR, a personal blog)
> • Article reading: tap any article; the reader should extract clean text and images
> • Article summary: open any long article and tap "Summarize"
> • Article chat: open any article, tap the circular logo bottom-right, ask a question
> • iCloud sync: enable in Account tab, verify feeds appear on a second device
> • Background refresh: leave the app for >15 min, return — new articles should be present
>
> Known limitations: push notifications entitlement is present but the feature is not wired up yet.
