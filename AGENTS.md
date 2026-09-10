# Working on Porch

Porch is a free, experimental native iOS Instagram client. Read DESIGN.md and VERIFICATION.md for the current architecture and evidence. The user explicitly replaced the earlier page-pruning approach with direct authenticated data requests and native rendering. Do not restore the browser-filter architecture.

Use project.yml and XcodeGen. Sources/InstagramBrowser.swift is for sign-in only. Sources/InstagramDataClient.swift owns the empty local WebKit transport. Sources/Resources/instagram-data.js owns the bounded, read-only adapter. NativeContent.swift and NativeStoriesAndMessages.swift own live content rendering. No Instagram application HTML or scripts should load for reading.

Credentials stay in the local WebKit store. Content may cross into bounded native models in memory; cookies, tokens, raw responses and private screenshots must not be logged or published. Tests use synthetic fixtures unless the explicit account scheme is invoked. Never follow, like, post or send a test message. Do not mistake sample or fixture results for signed-in evidence.

Feed and Stories are completely separate. Keep the single compact control row, black canvas, bone text and neutral grays. No bottom navigation, promotional copy, autoplay, story timers, infinite-scroll triggers, subscriptions, payment gates, app analytics or guilt counters. Whole rows should be tappable and controls at least 44 points.

Use the local ios-run workflow when available, otherwise README commands. Visually inspect UI changes. Commit scoped, verified source; never publish account data or signing material. This is an experimental source release, not an App Store submission.
