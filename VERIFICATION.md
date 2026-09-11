# Verification

September 11, 2026. Porch **0.2 (8)** is built locally; **0.2 (7)** was read back from the operator's phone. This is an internal iteration, not a UAT-readiness claim. Xcode 26.6 / Swift 6.3.3; simulator iOS 26.5. Deployment target iOS 18; iOS 18 itself has not been tested.

## DM failure investigation

The operator reported signing in and receiving a DM rejection. The exact live HTTP response remains uncollected. Build 7 discarded HTTP 400 response bodies before looking for authentication challenges or rate limits. A synthetic before/after check reproduced all three known categories—challenge, rate limit and explicit restriction—being mislabeled as a generic send rejection. Build 8 reads the envelope first, shows the corresponding recovery state, and retains a fixed-category send diagnostic across later conversation reads. It does not retain server text, challenge URLs, message bodies or account identifiers in diagnostics.

The final offline suite passed **31 test definitions / 47 expanded cases**, with zero failures: `artifacts/private/dm-error-final.xcresult`. New cases cover HTTP 400/403 recovery categories, unknown responses, missing receipts, diagnostic redaction, retained drafts and the distinction between a definite refusal and an uncertain send. The [fictional blocked composer](docs/images/blocked-send.png) was visually inspected. No automated live send was attempted. This patch repairs error handling; it does not establish the cause of the operator's failure or prove live delivery.

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

The build 7 installation log reported success followed by a locked-phone launch failure. On September 11, an exact `devicectl` bundle query independently confirmed **dev.alex.porch, version 0.2, build 7** on the paired iPhone 14 Pro Max; the private result is `artifacts/private/dm-installed-before.json`. The operator subsequently reported signing in and attempting a DM. The current phone session was retained while awaiting its diagnostic report, because its draft and diagnostic are in memory. Build 8 has not been installed on that phone.

The unsigned device Release archive succeeded at `.build-uat/Porch.xcarchive`; its version/build are 0.2/8. Debug fixture and authentication-bypass launch flags are absent from the Release executable, and the bundled adapter matches the verified source. Signing/distribution remain with the operator's homegrown workflow. Earlier build 2 had four passing physical-device playback and fictional-composer checks; those are historical evidence, not acceptance of build 8.

## Before friend UAT

- Exercise account-challenge and 2FA recovery on the physical phone. The operator reported a successful sign-in, but did not report which challenges were presented. External providers such as Facebook are not supported by this sign-in view.
- Diagnose the operator's rejected send, then verify one explicitly authorized real text send and a reply in a populated conversation. Fixture acknowledgement does not prove live delivery.
- Check audible playback, background/foreground behavior, and the operator's chosen Release installation workflow.
- Obtain hands-on review of the larger, centered layout. Passing tests and screenshots do not substitute for that review.

Instagram's unofficial routes and response shapes can change. This remains an experimental source release. The proposed friend journey is in [docs/UAT.md](docs/UAT.md).
