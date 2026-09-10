# Design

Porch serves people who already know Instagram and want less stimulation. Its content is fully custom, native SwiftUI. Black, warm bone, neutral gray and thin rules follow the restraint of Plural and Light Phone. One compact control row selects Feed, Stories or Messages. Explanations belong in Settings.

**Feed and Stories are separate destinations.** No story tray in Feed, no posts under Stories, no simultaneous streams. A story opens only after selecting a followed person. Advancement and video playback require a deliberate action. Pagination is a button, not an infinite-scroll trigger. The current session caches each tab until explicitly refreshed.

## Data path

1. `InstagramBrowser` owns the real Instagram sign-in sheet and its normal persistent WebKit store. Authentication and challenges stay on Instagram.
2. `InstagramDataClient` owns an empty local WebKit document with that same cookie store. Website JavaScript is disabled; only the bundled adapter runs in the app's content world. It loads no Instagram application HTML or scripts.
3. `instagram-data.js` makes allowlisted, authenticated GET requests. It validates expected response shapes, identifies followed authors, removes recognized unwanted content, caps arrays and text, and returns a JSON model no larger than 1 MB.
4. SwiftUI renders the models. Media URLs are restricted to HTTPS Instagram CDN hosts; native media fetches do not receive session cookies from Porch. Videos are created on Play and stopped on disappearance, tab/carousel changes, or backgrounding.

The Following endpoint must return `pagination_source: following`. The request uses that exact parameter; the website's `variant=following` query is not a substitute. Unknown modules are discarded. Ads, paid partnerships and clips are excluded. Missing positive following status excludes an author. Stories use the same positive relationship rule. Story and conversation detail IDs must have appeared in the corresponding list.

The adapter does not mark stories/messages seen, send, like, follow or post. The inbox excludes pending requests. Conversation support is limited to the most recent 20 messages, with placeholders for attachments. Stories are bounded to 50 people and 30 items per person. These are visible-data limits, not claims that an account contains no other content.

## Failure behavior

HTTP 401/403 and explicit login-required responses request sign-in. Rate limits stop requests for at least 60 seconds; nothing retries automatically. Fetches time out after 15 seconds. Unrecognized response contracts show a load failure instead of a successful empty view. End session releases the transport and content models while retaining sign-in. Clear sign-in additionally clears WebKit website data and the shared URL response cache.

Instagram controls authentication, rate limits and data availability. These unofficial contracts can change. No App Store submission, Screen Time integration, NFC hardware, push service or backend is part of this release.

## Evidence

Synthetic WebKit fixtures establish adapter behavior. The offline UI journey establishes sample navigation. Separate opt-in signed-in checks establish actual feed/story/inbox data and native UI behavior. A fixture, sample, or login-page screenshot is never proof of live content. See [VERIFICATION.md](VERIFICATION.md).
