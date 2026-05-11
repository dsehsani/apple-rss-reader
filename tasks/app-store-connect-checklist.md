# App Store Connect Submission Checklist — OpenRSS

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

### User Content

- **Other User Content** — **Yes, we collect this** (RSS feed subscriptions, folders, bookmarks, reading state stored in the user's private CloudKit database)
  - Is it linked to the user's identity? **Yes**
  - Is it used to track the user? **No**
  - Purpose: **App Functionality** (sync across devices)

### All Other Categories

Answer **No** for every other category:
- Health & Fitness: No
- Financial Info: No
- Location: No
- Sensitive Info: No
- Contacts: No
- Browsing History: No
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
- [ ] Policy has a contact email address
- [ ] Policy has an effective date
- [ ] In-app Settings → "About" section shows the Privacy Policy link
- [ ] Account screen shows "By signing in you agree to our Privacy Policy" under the Sign in with Apple button
