# What Instagram receives from Porch

September 11, 2026. This audit describes observable client behavior and the build 10 changes. It does not infer Instagram's private account-risk score or attribute the earlier HTTP 400 to an unobserved cause.

## Request profile

| Surface | Porch's behavior | What this establishes |
| --- | --- | --- |
| Sign-in | Instagram's own page in a persistent, app-local `WKWebView` store | A separate browser session from the Instagram app. A new-device notification is consistent with that sign-in. |
| Browser identity | WebKit's default user agent for both authentication and reads | The app does not override the user agent. The controlled comparison found the same identity in local-document and normally loaded-page modes. |
| Network | Direct HTTPS from the device to Instagram; media goes to its CDNs | Instagram sees the connection's egress address, which may change with Wi-Fi, cellular or a VPN. Logs retain network categories, not addresses. |
| Data requests | Web app ID `936619743392459`, XMLHttpRequest header, current CSRF cookie, authenticated same-origin fetch | These are web requests to unofficial data routes. They are not the Instagram iOS application's protocol or a promise of compatibility with every account. |
| Document | Empty local HTML based at `https://www.instagram.com/`; bundled adapter in an isolated content world | The loopback comparison found a valid POST Origin, sent cookies and the same Fetch Metadata headers. The local document's Referer path was `/`; the ordinary fixture page's was `/page`. |
| Session claim | Bootstrap value `0`; build 10 reuses valid `X-IG-Set-WWW-Claim` response values in that WebKit context | Previously every request used `0`, even after a server update. Claim values remain in WebKit memory, reset with account/CSRF context, and never enter logs. |
| Activity | Explicit bounded reads and text sends; no automatic send retry | This differs from the full application's background requests and telemetry. Request sequence, intervals and outcomes are now recorded for diagnosis. |
| Media | Native image/video fetches with no Instagram session cookies supplied by Porch | A separate native request path, intentionally limited to CDN media. |

[Meta describes unfamiliar-login notifications](https://about.fb.com/news/2021/07/keeping-instagram-safe-and-secure/) as account-security checks. The notification alone does not identify a malformed data request or an enforcement action.

## Concrete fixes

Ordinary JavaScript JSON parsing rounds integer values beyond `Number.MAX_SAFE_INTEGER`. The baseline fixture converted a 36-digit ID to scientific notation. Depending on its size, an affected ID could be omitted by validation or changed before being sent. Build 10 preserves the exact spelling of large integer tokens before JSON parsing, including conversation, message, receipt and client-context IDs. Strings and escapes remain intact; unsafe numeric IDs in other notation cannot become accepted recipients or receipts. This is a proven decoding defect, not proof that the earlier server response contained such a number.

Server claim updates now survive successive requests in the same WebKit context. A new account clears adapter membership and cursor state; a changed CSRF cookie resets the claim. Bootstrap uses the existing value `0`. Claims are bounded and must be valid header text. The [reference request implementation](https://github.com/dilame/instagram-private-api/blob/master/src/core/request.ts) likewise consumes this response header and maintains exact large IDs; it is independent implementation evidence, not Meta documentation or a live acceptance test.

Nested error reasons, challenge/two-factor structures and explicit spam flags now retain their recovery category. Invalid JSON or HTML failures can be grouped by a keyed fingerprint without preserving their text. Server-requested pauses longer than a day are no longer shortened to one day; the existing 60-second minimum and no-retry behavior remain. The pause applies to the active client/transport, not across app relaunches.

## Diagnostic evidence

Build 10 records the effective document/location origin categories, WebKit family, mobile/Safari markers, secure-context flag, claim bootstrap/update/reset category, request sequence and interval, parse outcome, count of preserved large integers, response type, server-status category and the source of a recognized error. A separate `requestContext` event records cookie-jar presence flags queried after WebKit prepares and before sends. These queries are asynchronous and do not delay dispatch; the event timestamp records when the snapshot arrives. Cookie-jar presence is not a claim that the wire contained a cookie.

The isolated adapter's schema and the native/export sanitizers remain closed. Tokens, cookie values, raw user-agent strings, URLs, IDs and message bodies are excluded. See [the diagnostic contract](DIAGNOSTICS.md).

## Verification boundaries

`WebKitWireTests` uses a loopback-only HTTP server, disposable server-set cookies and fictional inbox/thread/send responses. It compares Porch's local-document/client-world mode against a normally loaded HTML page/page world using real iOS WebKit requests. Both sent session/CSRF data, the received fixture claim and a matching POST Origin; both reported `Sec-Fetch-Site: same-origin`, `Sec-Fetch-Mode: cors` and `Sec-Fetch-Dest: empty`.

The first fixture attempted native cookie-store writes for an IP domain; neither mode received those cookies. Establishing the disposable session through server `Set-Cookie` responses corrected the fixture. The final comparison passed. The harness omits the production app-bound navigation restriction because its host is loopback; production's Instagram-only restriction is unchanged. It does not compare TLS or the current signed-in Instagram application. An existing browser session could not be inspected while the Mac was locked.

The available physical-device build 9 trace contained a session-verification timeout and no DM attempt. It supplies no HTTP response for the earlier build 7 rejection. Raw device traces and test results remain under ignored `artifacts/private/`; only the synthetic comparison and implementation conclusions are described here.

The next actual failed request can distinguish an explicit Instagram challenge/restriction, an unclassified server refusal, a malformed response, a local validation failure and a network timeout. A successful fixture does not establish live message acceptance or explain Meta's internal risk decision.
