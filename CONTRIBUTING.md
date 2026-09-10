# Contributing

Build with XcodeGen and Xcode. The project has no third-party runtime dependencies.

Keep content native, and keep Feed, Stories and Messages separate. Preserve the compact control row, readable contrast, Dynamic Type and 44-point touch targets. No autoplay, forced engagement, subscriptions, paid unlocks, ads or app analytics.

For adapter changes, extend `Tests/DataAdapterTests.swift`: include unwanted content and a similar legitimate example that must survive. These fixtures run the production adapter in actual WebKit without an account. Preserve exact-host HTTPS authentication navigation, positive following checks, detail-ID membership checks and bounded models. Schema failures must not look like empty success. Do not add automatic retry loops.

Credentials remain in WebKit. Never log cookies, tokens, raw responses or account content. Keep account actions out of tests. Signed-in verification belongs to the explicit `PorchAccountCheck` scheme; retain its screenshots privately and report only route/status/count observations.

Use `project.yml`; generated projects, build outputs, signing material, private screenshots and result bundles are ignored. Run the build and checks appropriate to a change, inspect UI changes on the simulator, and run `git diff --check` before submitting a pull request.

Original source contributions are MPL-2.0. Record third-party assets and licenses in `THIRD_PARTY_NOTICES.md`.
