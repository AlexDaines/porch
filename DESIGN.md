# Porch

An Instagram browser for keeping up with people, with no subscription, purchase unlock, analytics, or app backend. Working name; independent of Instagram and Meta.

## first usable slice

SwiftUI navigation around Instagram's own website in WKWebView. Sign in directly on instagram.com; WebKit keeps the session in this app's on-device website store. Do not read credentials, cookies, private API responses, or message bodies into native code. Native tabs open Following, stories (via home story tray), and the inbox. A local people list opens profiles the user deliberately adds; following alone does not prove a person is a real-life friend.

At document start, bundled local CSS/JavaScript removes Reels/Explore navigation, blocks matching full-page and same-page routes, and hides feed cards bearing recognized ad, recommendation, or reel markers. Conservative DOM rules must preserve normal photos, login/challenge screens, profile pages, the story tray, and the inbox. No claims of perfect filtering: Instagram can change its markup, account experiments and language. Surface filter health with a useful retry path. No server proxy, unofficial API, scraping pipeline, automated likes or messages.

A clearly marked, fully offline sample lets a contributor inspect the design without an account. It is separate from the actual Instagram browser and cannot be represented as live integration evidence. The sample offers finite posts, manual story advancement and fictional local conversations. It never sends messages.

## native experience

Black canvas, warm bone text, one amber accent. Familiar header / story circles / photo cards / bottom navigation. Dynamic Type, accessible labels, at least 44-point targets, no required motion. Welcome explains what the app does and what it cannot guarantee. An explicit finish-session action dismisses content; no streaks, guilt counters, urgency badges, or engagement prompts. Local people and appearance choices persist with UserDefaults. Website data can be cleared from settings with explicit confirmation.

## scope boundary

No NFC device, VPN, Screen Time entitlement, Android port, push notifications, payments, or App Store submission in this slice. This app filters its own embedded browser; it does not modify or block the Instagram app. Instagram controls authentication, account restrictions, site tracking and availability. Ads are hidden from view, not guaranteed never downloaded. Blocking reel routes also blocks reels shared by friends. Story ad heuristics require real-account validation; no automatic story advancement is promised.

## acceptance evidence

- App builds, launches and is visually inspected on the iOS simulator.
- URL policy accepts exact Instagram HTTPS hosts and rejects spoof hosts, unexpected schemes and encoded blocked routes.
- Bundled filter runs against adversarial DOM fixtures: ads/recommendations/reels hidden, ordinary captions and DMs preserved, dynamically inserted cards filtered, repeated passes stable, SPA routes blocked.
- Native UI is exercised through welcome, offline sample, people, settings and the live sign-in page.
- Signed-in posts/stories/inbox behavior is recorded separately. A login wall or fixture pass cannot prove it.

## status

Scaffold created. Features and verification pending. Public source release follows implementation and a secret/data review. No user account content belongs in the repository or screenshots.
