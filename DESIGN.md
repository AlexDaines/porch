# Design

Porch serves people who already know Instagram and want less stimulation. Its content is fully custom, native SwiftUI. The visual reference is Plural, the moped travel-time app, and its Horse Weapons style: black canvas, warm bone text, warm gray details, thin rules and lime for active controls. One compact control row selects Feed, Stories or Messages. Explanations belong in Settings.

Monospaced utility labels and the short lime selection underline come from Plural's controls. Names and captions retain readable system typography, with the author above the media and the caption below. Content is left-aligned with 20-point text margins; photos can span the screen. The navigation stacks at large text sizes instead of truncating its labels. No extra masthead, counters or decorative panels compete with the content.

**Feed and Stories are separate destinations.** No story tray in Feed, no posts under Stories, no simultaneous streams. A story opens only after selecting a followed person. Advancement and video playback require a deliberate action. Pagination is a button, not an infinite-scroll trigger. The current session caches each tab until explicitly refreshed.

## Data path

1. `InstagramBrowser` owns the real Instagram sign-in sheet and its normal persistent WebKit store. Authentication and challenges stay on Instagram.
2. `WebKitInstagramTransport` owns an empty local WebKit document with that same cookie store. Website JavaScript is disabled; only the bundled adapter runs in the app's content world. It loads no Instagram application HTML or scripts.
3. `instagram-data.js` makes allowlisted, authenticated GET requests and one explicit text-send POST. It validates expected response shapes, identifies followed authors, removes recognized unwanted content, caps arrays and text, and returns a JSON model no larger than 1 MB.
4. SwiftUI renders the models. Media URLs are restricted to HTTPS Instagram CDN hosts; native media fetches do not receive session cookies from Porch. Videos are created on Play and stopped on disappearance, tab/carousel changes, or backgrounding.

The Following endpoint must return `pagination_source: following`. The request uses that exact parameter; the website's `variant=following` query is not a substitute. Unknown modules are discarded. Ads, paid partnerships and clips are excluded. Missing positive following status excludes an author. Stories use the same positive relationship rule. Story and conversation detail IDs must have appeared in the corresponding list.

The adapter makes no seen-marker, like, follow or posting requests. Text sending is restricted to a conversation in the accepted inbox that has been opened, and requires a deliberate Send action. The inbox excludes pending requests. Conversations and inbox pages load 20 records at a time, with explicit controls for earlier records and a 200-record session bound. Non-text attachments have descriptive placeholders. Group sender names are retained when provided. Stories are bounded to 50 people and 30 items per person. These are visible-data limits, not claims that an account contains no other content.

## Failure behavior

HTTP 401/403 and explicit login-required responses request sign-in. Rate limits stop both queued and new requests for at least 60 seconds, respecting longer Retry-After values up to a day; nothing retries automatically. Fetches time out after 15 seconds. Unrecognized response contracts show a load failure instead of a successful empty view. Requests are serialized; session generations reject late results after closing. Errors remain local to their destination. A failed refresh preserves existing content. End session releases the transport, content models and in-memory drafts while retaining sign-in and unresolved send identifiers. Clear sign-in additionally clears WebKit website data, the shared URL response cache and unresolved send identifiers.

Instagram controls authentication, rate limits and data availability. These unofficial contracts can change. No App Store submission, Screen Time integration, NFC hardware, push service or backend is part of this release.

## Text sending

The only mutation is `/api/v1/direct_v2/threads/broadcast/text/`, with form-encoded text, an accepted thread ID and one generated client context. Input is bounded to 1,000 UTF-16 code units. The same context is used for the mutation and offline-threading fields. A valid server item receipt is required before displaying Sent; that status does not claim delivery to the recipient. No automatic send retries occur.

A journal of conversation ID, request context and timestamp is written before dispatch, without the message body. A timeout, malformed response or app exit leaves the send unresolved and disables another send to that conversation. Checking the conversation can reconcile a matching outgoing context. Otherwise the user must explicitly clear the warning after checking Instagram; this also clears the draft and never resends it. Known rejection preserves the draft for correction. The current contract follows the open-source [instagrapi direct-send implementation](https://github.com/subzeroid/instagrapi/blob/master/instagrapi/mixins/direct.py); a fixture validates our encoding, not Instagram's live acceptance.

## Evidence

Synthetic WebKit fixtures establish adapter behavior. The offline UI journey establishes sample navigation. Separate opt-in signed-in checks establish actual feed/story/inbox data and native UI behavior. A fixture, sample, or login-page screenshot is never proof of live content. See [VERIFICATION.md](VERIFICATION.md).
