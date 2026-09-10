# Native data client

The user challenged the cost and fragility of loading all of Instagram and pruning it in real time. The missing experiment was direct authenticated data access. No official consumer-feed integration does not mean no possible local client.

An empty local WKWebView document, based at instagram.com and sharing the existing sign-in store, successfully made authenticated GET requests while Instagram website JavaScript was disabled. The bundled adapter runs in the app's isolated content world. It returns small content models to SwiftUI; it does not copy cookies into native networking or run Instagram's renderer.

The decisive feed parameter is `pagination_source=following`. A request using only the website-style `variant=following` returned different data and did not establish a Following feed. The correct response identified its pagination source and each retained author's positive following status. Four actual posts rendered in native SwiftUI; a followed person's active story and the accepted empty inbox also loaded. Exact final checks are in VERIFICATION.md.

The integration is read-only and local. Instagram's HTML is loaded only for login/challenges. Feed, Stories and Messages have independent views and deliberate entry. There is no automatic story advancement, feed pagination or video playback. Unofficial endpoint changes remain a compatibility risk, concentrated in the small adapter.
