# Design

Porch serves people who already know Instagram and want less stimulation. Its content is fully custom, native SwiftUI. The visual reference is Plural, the moped travel-time app, and its Horse Weapons style: black canvas, warm bone text, warm gray details, thin rules and a personal accent for active controls. One compact control row selects Feed, Stories or Messages. Explanations belong in Settings.

Monospaced utility labels and the short selection underline come from Plural's controls. Names and captions retain readable system typography, with the author above the media and the caption below. Entry screens, control groups and sheet titles are centered. Reading paragraphs retain 20-point text margins; photos can span the screen. The navigation stacks at large text sizes instead of truncating its labels. No extra masthead, counters or decorative panels compete with the content.

Every Porch interface shape has sharp corners. Swatches, selection outlines, avatars, play-button backgrounds and message fields are rectangular. App sheets explicitly use a zero corner radius and no drag handle. Settings uses a plain header; confirmations appear inline with explicit confirm and cancel actions. This rule governs Porch's surfaces; Instagram authentication and OS-owned keyboards, sharing and playback controls retain their own rendering.

## Color introduction

The user's [Light Phone](https://www.thelightphone.com/) reference informs the restraint, not miniature text. After rejecting the previous tiny scale, the user asked for larger text and centered elements. Body text and names are 17 points, details and monospaced utilities are 15 points, and onboarding headings are 22 points. Native Dynamic Type styles retain accessibility scaling. Story avatars are 32 points by default and scale with their initials. The three navigation labels form a centered group with equal space on either side; the Settings control occupies the trailing space. At accessibility sizes, the controls stack in the center. Sheet titles use equal-width side spaces so the close button cannot pull a title off-center. Names use medium weight; reading copy remains regular.

The first launch asks only “Choose a color.” Five 28-point square swatches, a selected checkmark and a Continue action form one centered group on the black canvas. Sage is preselected so the user can continue without making a decision. There are no timers, automatic transitions, notifications, permissions or Instagram requests in this introduction. Its completion and the chosen color are stored locally. Settings → Color offers the same choices and applies changes immediately to navigation, actions and the native composer. The choice survives session finish and clearing Instagram sign-in.

| Choice | Accent |
| --- | --- |
| Sage | `#A6B8A0` |
| Sea | `#94B8B1` |
| Mist | `#9FB7C7` |
| Lilac | `#B5ADC6` |
| Sand | `#C6BDAA` |

These are design choices informed by research, not validated therapeutic colors. [Wilms and Oberfeld](https://doi.org/10.1007/s00426-017-0880-8) found that saturation and brightness, as well as hue, affected arousal in their display experiment; blue and green elicited lower arousal ratings than red. That finding informs the muted blue/green options, but does not validate these exact hex values or establish addiction outcomes. Lilac and Sand broaden personal preference. [Jonauskaite and colleagues](https://doi.org/10.1177/0956797620948810) found shared color-emotion associations alongside linguistic/geographic differences. The interface makes no universal calming claim.

Accent contrast is at least 9.7:1 against black and 8.8:1 against the raised surface. Color is accompanied by labels and a checkmark. Each small swatch has a separate 44 × 44-point tap target; text actions and rows also preserve at least 44 points. The page scrolls when larger text needs more room. Original media sizes and colors remain intact.

The system launch screen uses an explicit black color asset and dark appearance, matching the native canvas before SwiftUI loads. [Apple's launch-background key](https://developer.apple.com/documentation/bundleresources/information-property-list/uilaunchscreen/uicolorname) otherwise defaults to the device's system background; that produced a white startup flash on a device using light appearance.

**Feed and Stories are separate destinations.** No story tray in Feed, no posts under Stories, no simultaneous streams. A story opens only after selecting a followed person. Advancement and video playback require a deliberate action. Pagination is a button, not an infinite-scroll trigger. The current session caches each tab until explicitly refreshed.

## Sign-in journey

After choosing a color, “Sign in to Instagram” opens the real authentication page immediately. It never opens a feed to discover whether sign-in is needed. Cancel returns to the entry screen and invalidates pending checks; a late result cannot enter the app. Instagram handles credentials and challenges. Cookie changes and completed navigation trigger verification. Porch opens automatically after success, leaving Instagram’s form with one clear Log in action. Incomplete sign-in stays in the form; a failed connection check offers an explicit retry.

On returning launches, an empty local WebKit document checks for the account cookie and reports only its presence. This makes no Instagram request. A fresh WebKit cookie-store query returned empty before initialization on the tested device; the local probe avoids mistaking that for a signed-out account. [WebKit's app-bound documentation](https://webkit.org/blog/10882/app-bound-domains/) describes the relevant cookie/API restrictions.

A saved-session hint offers “Open Porch”. Tapping verifies authentication with a bounded accepted-inbox GET; only success/error crosses to native code, with no conversation content. An expired session opens sign-in; connectivity failures stay on the entry screen with retry and Sign in again available. The same validation governs a new login. Cookie presence and URLs never establish success alone. Failed network checks do not retry automatically. The browser has a bounded load timeout, and retry mounts a new web view.

Authentication currently supports Instagram-hosted username/password and challenge pages. External sign-in options such as Facebook show an explanation; they are not silently treated as completed authentication.

## Data path

1. `InstagramBrowser` owns the real Instagram sign-in sheet and its normal persistent WebKit store. Authentication and challenges stay on Instagram.
2. `WebKitInstagramTransport` owns an empty local WebKit document with that same cookie store. Website JavaScript is disabled; only the bundled adapter runs in the app's content world. It loads no Instagram application HTML or scripts.
3. `instagram-data.js` makes allowlisted, authenticated GET requests and one explicit text-send POST. It validates expected response shapes, identifies followed authors, removes recognized unwanted content, caps arrays and text, and returns a JSON model no larger than 1 MB.
4. SwiftUI renders the models. Media URLs are restricted to HTTPS Instagram CDN hosts; native media fetches do not receive session cookies from Porch. Videos are created on Play and stopped on disappearance, tab/carousel changes, or backgrounding.

The Following endpoint must return `pagination_source: following`. The request uses that exact parameter; the website's `variant=following` query is not a substitute. Unknown modules are discarded. Ads, paid partnerships and clips are excluded. Missing positive following status excludes an author. Stories use the same positive relationship rule. Story and conversation detail IDs must have appeared in the corresponding list.

The adapter makes no seen-marker, like, follow or posting requests. Text sending is restricted to a conversation in the accepted inbox that has been opened, and requires a deliberate Send action. The inbox excludes pending requests. Conversations and inbox pages load 20 records at a time, with explicit controls for earlier records and a 200-record session bound. Non-text attachments have descriptive placeholders. Group sender names are retained when provided. Stories are bounded to 50 people and 30 items per person. These are visible-data limits, not claims that an account contains no other content.

## Failure behavior

Error envelopes are read before generic HTTP failures. Login, challenge, checkpoint and two-factor responses request sign-in even when Instagram returns HTTP 400. Explicit feedback and sentry restrictions have their own failure state; remaining HTTP 401/403 responses request sign-in. HTTP 429 and the `rate_limit_error` envelope stop both queued and new requests for at least 60 seconds, respecting longer valid Retry-After values for the lifetime of that client/transport; nothing retries automatically. Fetches time out after 15 seconds. Unrecognized response contracts show a load failure instead of a successful empty view. Requests are serialized; session generations reject late results after closing. Errors remain local to their destination. A failed refresh preserves existing content. End session releases the transport, content models and in-memory drafts while retaining sign-in and unresolved send identifiers. Clear sign-in additionally clears WebKit website data, the shared URL response cache and unresolved send identifiers.

Diagnostics are always enabled locally in Debug and Release. A bounded, protected JSONL timeline survives restarts and records app/build, lifecycle, network state, authentication transitions, serialized request stages/timing, fixed response shapes, filtering counts, native media failures and DM preparation, refusal, acknowledgement and reconciliation. Request UUIDs and installation-keyed HMAC references connect the events without exposing account IDs or message context. Unknown error envelopes and non-JSON failures are fingerprinted inside the isolated adapter; their text does not enter native diagnostics. Build 10 adds actual origin/browser categories, cookie-jar metadata, claim state, request cadence, parse evidence and nested/structural error categories. See [the request audit](docs/REQUESTS.md) for measured behavior and its limits.

Settings → Diagnostics → Share log creates a sanitized JSON file and opens the system share sheet. The trace budget is ten 2 MiB segments and 14 days, plus one replaceable export. No log is uploaded automatically. Files are excluded from backups and use iOS protection until first unlock. Credentials, usernames, message bodies, raw responses, identifying URLs and exception descriptions are excluded at both write and export boundaries. Clear log removes traces and the export independently of sign-in and the unresolved-send journal. MetricKit records bounded binary UUID/offset stacks when iOS delivers crash, hang or resource diagnostics; it cannot guarantee a report for every termination. See [diagnostics contract](docs/DIAGNOSTICS.md).

Instagram controls authentication, rate limits and data availability. These unofficial contracts can change. No App Store submission, Screen Time integration, NFC hardware, push service or backend is part of this release.

## Text sending

The only mutation is `/api/v1/direct_v2/threads/broadcast/text/`, with form-encoded text, an accepted thread ID and one generated client context. Input is bounded to 1,000 UTF-16 code units. The same context is used for the mutation and offline-threading fields. Large integer JSON tokens are preserved exactly before parsing, and unsafe numeric forms cannot become accepted recipient or receipt IDs. Server-issued web claim updates stay in the adapter context and reset when account/CSRF context changes. A valid server item receipt is required before displaying Sent; that status does not claim delivery to the recipient. No automatic send retries occur.

A journal of conversation ID, request context and timestamp is written before dispatch, without the message body. A timeout, malformed response or app exit leaves the send unresolved and disables another send to that conversation. Checking the conversation can reconcile a matching outgoing context. Otherwise the user must explicitly clear the warning after checking Instagram; this also clears the draft and never resends it. Known rejection preserves the draft for correction. The current contract follows the open-source [instagrapi direct-send implementation](https://github.com/subzeroid/instagrapi/blob/master/instagrapi/mixins/direct.py); a fixture validates our encoding, not Instagram's live acceptance.

## Evidence

Synthetic WebKit fixtures establish adapter behavior. The offline UI journey establishes sample navigation. Separate opt-in signed-in checks establish actual feed/story/inbox data and native UI behavior. A fixture, sample, or login-page screenshot is never proof of live content. See [VERIFICATION.md](VERIFICATION.md).
