# Verification

September 11, 2026. Porch **0.2 (10)** is built locally and installed on the operator's phone; its exact bundle/build was independently read back. The first build 10 launch verified the new on-device diagnostic fields. The final schema correction is installed, but automatic launch was declined while the phone required a passcode. This is an internal iteration, not a UAT-readiness claim. Xcode 26.6 / Swift 6.3.3; simulator iOS 26.5. Deployment target iOS 18; iOS 18 itself has not been tested.

## Request compatibility refinement

Build 10 preserves large numeric JSON identifiers, consumes server-issued web claim updates within the original browser/account/CSRF context, recognizes nested/structured refusal reasons and respects active-session Retry-After values longer than one day. Cookie metadata is sampled asynchronously without delaying dispatch. Origin/browser categories, claim state, request cadence, parse evidence and private fingerprints supplement the existing persistent log.

The full offline suite passed **46 test definitions**, with no failures or skips (`artifacts/private/refinement-full.xcresult`). After the final non-blocking cookie observation and copied-reason cleanup, all **40 unit/adapter definitions** passed again (`artifacts/private/refinement-final-unit.xcresult`). The physical trace then exposed the existing `savedSession` hint missing from the closed diagnostic schema. Its fixed present/absent values are now accepted; the focused session/diagnostics suite passed again (8 tests, `artifacts/private/refinement-schema-final.xcresult`). No application screens changed. The existing fictional rejection, restart/export and uncertain-send reconciliation UI flows passed in the full run.

A prior CI run exposed a keyboard-focus failure in a fictional composer test. The four composer journeys now wait for the keyboard, focus the field at its settled position and verify the entered draft before sending. CI runs tests serially, matching local verification. All four journeys passed again with no failures (`artifacts/private/refinement-ui-readiness.xcresult`). These changes affect tests and CI only; the installed build and Release archive are unchanged.

CI also exposed an OS-specific share-sheet assertion: its accessibility snapshot showed `Porch-diagnostics.json` in the bottom caption, while the local simulator showed `Porch-diagnostics` in the top caption. The test now waits for either observed filename label instead of relying on a private framework identifier. The focused diagnostic restart/export journey passed (`artifacts/private/refinement-share-filename.xcresult`).

A later CI run reported an internal WebKit `InvalidTransition` error in the loopback fixture and an unexpected latest-failure summary after the UI restart. The summary text was not captured, so this does not establish lost log data. Saved local fixture traces did reveal an unintended session-hint probe on each fictional native launch: the welcome page briefly mounted before `--native` took effect. That Debug route now starts in native mode before rendering. All four UI journeys and the loopback test passed (`artifacts/private/refinement-fixture-isolation.xcresult`); the five UI launches recorded zero session-probe events, with the expected send outcomes retained. This changes fixture startup only; normal app startup and Release behavior are unchanged.

The loopback harness now closes on failure and reports its fixed loading stage. Failed summary assertions include the actual fixed-category label. Full result bundles and trace files remain local; CI does not upload them. CI also checks Release compilation when a test fails. This improves evidence for another failure without weakening assertions or retrying messages.

A real iOS WebKit loopback test compared an empty local document/client world with an ordinary loaded HTML page/page world. Both sent the same default user agent, the synthetic session/CSRF data, the returned claim, a matching POST Origin and the same Fetch Metadata categories. Referer paths differed as expected. Only fictional requests reached a loopback HTTP server; no Instagram message was sent. The initial loopback cookie fixture was corrected to use server Set-Cookie responses before the comparison passed. [Request audit](docs/REQUESTS.md) records the method, results and limits.

The final unsigned Release archive is `.build-uat/Porch.xcarchive` (0.2 / 10); build 9 is preserved at `.build-uat/Porch-0.2-9.xcarchive`. Fixture launch switches are absent from Release, diagnostic events remain present, the adapter matches source, and the executable/dSYM UUIDs match: `D4FBBCE4-84F0-305F-AC99-92A7AAA10694`. Archive log: `artifacts/private/refinement-release-final.log`.

The first build 10 phone launch recorded 13 events, including the new cookie-jar metadata and a successful local-only session hint. The actual device reported an Instagram document/location origin, a secure context and the default iOS WebKit family. Its saved-session field exposed the schema omission corrected above. The final signed bundle passed macOS signature verification, installed successfully and was independently read back as 0.2 (10); automatic launch then failed the iOS preflight. A separate lock-state query confirmed that a passcode was required. Final launch/log verification awaits opening the app on the phone. Evidence: `artifacts/private/refinement-device-install-final.log`, `build10-installed-final.json`, `build10-signature-verification.txt`, `build10-lock-state.json` and `build10-phone-verification.json`.

The available build 9 phone trace contains a session-verification timeout and no DM attempt. It does not establish the cause of the earlier build 7 HTTP 400. Device traces and all account-bearing artifacts remain private.

## Durable diagnostics

Build 9 adds always-on local diagnostics in Debug and Release. The offline suite passed **41 test definitions / 57 expanded cases**, with zero failures: `artifacts/private/logging-verified.xcresult`. A final-source unit/adapter run also passed **35 definitions / 51 expanded cases** with no failures (`artifacts/private/logging-unit-final.xcresult`). Tests exercise cross-launch correlation, rotation, retention and export expiration, private-data canaries, interrupted and tampered files, unavailable storage, clear/export behavior, safe underlying errors and MetricKit stack extraction. Adapter checks observe HTTP arrival before parsing, deterministic keyed fingerprints of unknown errors and unchanged single-dispatch send behavior. Legacy unresolved-send journals still decode.

The fictional UI journey sends into a synthetic HTTP 400 restriction, terminates and relaunches the app, finds the retained failure in Diagnostics and opens the generated JSON in the system share sheet. The first run used the wrong accessibility type for Copy (button versus cell); inspection showed the actual JSON share sheet, and the final assertion checks its collection and filename. The final [Diagnostics screen](docs/images/diagnostics.png) was inspected. The actual generated fixture export was read back separately: build 9, 224 events, zero storage/read errors and no private canary text. These results establish the diagnostic pipeline without sending any real messages.

The final Release compilation also verifies that fixture switches are excluded while durable diagnostics remain included. Every export carries current build metadata even if launch events have rotated out; iOS diagnostics retain their original build metadata. Actual iOS crash/hang delivery has not been induced or verified on the physical phone. MetricKit reports are OS-controlled and may be delayed or absent. Local logging cannot recover the operator's earlier build 7 attempt. Coverage, retention, privacy and interpretation are documented in [the diagnostics contract](docs/DIAGNOSTICS.md).

## DM failure investigation

The operator supplied a build 7 diagnostic from iOS 26.6.2: `View: sendText`, `HTTP: 400`, `Result: sendRejected`. This establishes the response status but not Instagram's underlying reason, because build 7 discarded the error envelope. Build 7 discarded HTTP 400 response bodies before looking for authentication challenges or rate limits. A synthetic before/after check reproduced all three known categories—challenge, rate limit and explicit restriction—being mislabeled as a generic send rejection. Build 8 reads the envelope first, shows the corresponding recovery state, and retains a fixed-category send diagnostic across later conversation reads. It does not retain server text, challenge URLs, message bodies or account identifiers in diagnostics.

Build 8’s offline suite passed **31 test definitions / 47 expanded cases**, with zero failures: `artifacts/private/dm-error-final.xcresult`. New cases cover HTTP 400/403 recovery categories, unknown responses, missing receipts, diagnostic redaction, retained drafts and the distinction between a definite refusal and an uncertain send. The [fictional blocked composer](docs/images/blocked-send.png) was visually inspected. No automated live send was attempted. This patch repairs error handling; it does not establish the cause of the operator's failure or prove live delivery.

## Layout and offline behavior

Build 7's offline Porch suite passed **27 test definitions / 43 expanded cases**, with no failures, on iPhone 17 Pro. Its clean-build result is `artifacts/private/verified-offline.xcresult`. Those checks are also included in build 8's passing suite above.

Build 7 replaces the rejected 13/12/11-point scale with 17-point body/name text, 15-point details and utility labels, and 22-point onboarding headings. Entry screens, swatches, navigation, sheet titles and Settings actions are centered. Swatches remain square and are now 28 points inside 44-point tap areas. App-owned surfaces retain sharp corners.

Normal-size introduction, entry, Settings, feed, Stories, story viewer, conversation and fictional composer screenshots were inspected. Maximum-accessibility introduction and navigation were checked separately. The UI journey also measures the entry button and color group's horizontal centers against the actual screen center. Public screenshots contain only fictional content or generic entry UI.

The fixture suites cover Following-only filtering, ads/Reels/recommendation exclusions, malformed schemas, explicit pagination, restricted media URLs, accepted/opened conversation membership, sender alignment, text encoding, server acknowledgement, duplicate-send prevention, unresolved-send recovery, rate limits and native playback. Automated tests never send real messages.

## Sign-in

The entry now opens Instagram authentication directly. Cancel returns to the entry and invalidates pending checks. Opening a page, finding a cookie or receiving a late response cannot establish sign-in. Successful authenticated verification opens the native app automatically. Connectivity failures have explicit retry paths.

The saved-session investigation reproduced a cold WebKit store returning zero cookies even while the existing session still worked through the local transport. A local-only adapter probe now initializes WebKit and returns a presence hint without an Instagram request. Verification uses a bounded authenticated inbox GET and returns no conversation content to native code. The account-profile endpoint considered during development was unavailable and is not used by the final implementation.

Synthetic connection tests cover immediate sign-in, incomplete authentication, cancellation, late success after cancellation, expired sessions, server verification, failures without automatic retries, and recovery when a new sign-in follows a connectivity failure. Adapter fixtures prove that the local hint makes no request and that malformed/unauthenticated responses cannot masquerade as a successful session.

The signed-out simulator journey starts at color selection, taps the actual entry button, reaches Instagram's secure password field, cancels back to the entry, and opens a new functioning sign-in view. It does not enter credentials. The final clean-build PorchLiveCheck passed its one UI journey on iPhone 17e: `artifacts/private/verified-sign-in.xcresult`. [Signed-out form](docs/images/sign-in.png). The shared Xcode cache had unexpectedly run an old login-page-only test; the final checks were rebuilt in a separate directory, and that stale run is not counted as journey evidence.

## Read-only account integration

Build 7's opt-in **PorchAccountCheck passed 3 tests** on iPhone 17 Pro. Final clean-build result: `artifacts/private/verified-account.xcresult`.

The tests verify saved-session discovery before content loading, an actual authenticated verification request, and the user-facing path from color selection through **Open Porch** into native Feed, Stories and inbox. The existing account supplies real posts and an active story group with two media items. A real video loaded as playable and advanced through AVPlayer. The accepted inbox was empty, so this check does not establish message rendering with real conversation content. Reading surfaces contain no web view. No follows, likes, posts, sends or seen-marker requests were performed. Private screenshots and result bundles remain excluded from git.

This establishes the existing session's restoration path. It does not establish a newly entered password, account challenge, 2FA flow or physical-phone login.

## Device and Release

On September 11, after the operator confirmed that the unsent draft was only a disposable test, the canonical device workflow installed **dev.alex.porch, version 0.2, build 9** on the paired iPhone 14 Pro Max and launched it successfully. An independent installed-app query confirmed version/build (`artifacts/private/build9-installed-app.json`). The physical device's protected diagnostic directory contains a trace file; a read-only copy of that sanitized trace records build 9, iOS 26.6.2, 15 startup events and no errors (`artifacts/private/build9-phone-startup.jsonl`). No real message was sent or retried by automation. This verifies deployment and device logging, not live DM delivery.

The code revision `75f7af1` also passed [GitHub's offline and Release checks](https://github.com/AlexDaines/porch/actions/runs/34581007069).

The historical build 9 unsigned device Release archive is preserved at `.build-uat/Porch-0.2-9.xcarchive`; its version/build are 0.2/9. The previous build 8 archive is preserved at `.build-uat/Porch-0.2-8.xcarchive`. Debug fixture and authentication-bypass launch flags are absent from that Release executable, and its bundled adapter matches the source verified for build 9. That Release binary contains the durable log/export and crash-event code; its dSYM UUID matches the app binary (`83E990C8-81E1-3679-A1A2-58D726095990`). Signing/distribution remain with the operator's homegrown workflow. Earlier build 2 had four passing physical-device playback and fictional-composer checks; those are historical evidence, not acceptance of build 9.

## Before friend UAT

- Exercise account-challenge and 2FA recovery on the physical phone. The operator reported a successful sign-in, but did not report which challenges were presented. External providers such as Facebook are not supported by this sign-in view.
- Diagnose the operator's rejected send, then verify one explicitly authorized real text send and a reply in a populated conversation. Fixture acknowledgement does not prove live delivery.
- Check audible playback, background/foreground behavior, and the operator's chosen Release installation workflow.
- Obtain hands-on review of the larger, centered layout. Passing tests and screenshots do not substitute for that review.

Instagram's unofficial routes and response shapes can change. This remains an experimental source release. The proposed friend journey is in [docs/UAT.md](docs/UAT.md).
