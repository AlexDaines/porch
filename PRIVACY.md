# Privacy

September 10, 2026.

Porch has no server, analytics, crash-reporting SDK, payment system, or separate account.

You sign in on Instagram's own HTTPS page inside Apple's WebKit. Passwords are entered into that page, not a native Porch form. WebKit stores the session locally. Porch does not extract or export the session cookie.

A separate empty local WebKit document uses that same session for reads and user-initiated text messages. The bundled adapter reads the CSRF cookie inside WebKit for request authentication and the local account ID for message alignment. Those values stay inside WebKit. It returns bounded post, story, inbox and message models to native memory for SwiftUI to display. Content is not logged, exported, or sent to a Porch backend.

Native image/video requests go directly to Instagram's media CDNs. Instagram and its media servers can observe requests. Porch is not a network anonymity tool. Excluding a record from the renderer does not prove Instagram did not include it in an API response or record the request.

Content models and drafts are held in memory. Before sending a DM, Porch saves only the conversation identifier, a random request identifier and a timestamp in local app preferences. This unresolved-attempt journal survives an app restart to prevent accidental duplicate sending. It contains no message body or credentials and is removed after acknowledgement or an explicit reset. Normal device backups may include these preferences. WebKit retains its normal website data; native media may use operating-system caches. Normal device backup behavior may apply. Porch implements no cloud sync or account-content export. Settings can share a report containing only app/build version, iOS version, operation name, HTTP status and a fixed error code; the user chooses whether and where to send it. End session clears content and drafts and releases the transport but retains sign-in. Settings → Clear sign-in removes the unresolved-send journal, the app's WebKit website data and shared URL-response cache; it does not revoke sessions on other devices.

The sample is entirely local, with fictional people/messages and one bundled landscape. It makes no Instagram requests. Source-code links open GitHub only when selected.

Account integration tests are opt-in and may retain screenshots and test diagnostics locally in Xcode result bundles. These are private artifacts, excluded from source control. Never attach raw account responses, credentials, private conversations or signed-in screenshots to a public issue. Use synthetic examples.
