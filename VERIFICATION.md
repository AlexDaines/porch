# Verification

September 10, 2026. Porch **0.2 (7)**. This is an internal iteration, not a UAT-readiness claim. Xcode 26.6 / Swift 6.3.3; simulator iOS 26.5. Deployment target iOS 18; iOS 18 itself has not been tested.

## Layout and offline behavior

The offline Porch suite passed **27 test definitions / 43 expanded cases**, with no failures, on iPhone 17 Pro. Final clean-build result: `artifacts/private/verified-offline.xcresult`. All four connection-state tests are included, with the final recovery change.

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

Build 7 was signed and installed on the paired iPhone 14 Pro Max. The phone was locked and refused launch, so physical interaction with this build remains unverified. The installation log is private at `artifacts/private/readable-device.log`.

The unsigned device Release archive succeeded at `.build-uat/Porch.xcarchive`; its version/build are 0.2/7. Debug fixture and authentication-bypass launch flags are absent from the Release executable. Signing/distribution remain with the operator’s homegrown workflow. Earlier build 2 had four passing physical-device playback and fictional-composer checks; those are historical evidence, not acceptance of build 7.

## Before friend UAT

- Complete fresh sign-in on the physical phone, including any account challenge or 2FA that Instagram presents. External providers such as Facebook are not supported by this sign-in view.
- Verify one explicitly authorized real text send and a reply in a populated conversation. Fixture acknowledgement does not prove live delivery. No real DM was sent during this iteration.
- Check audible playback, background/foreground behavior, and the operator's chosen Release installation workflow.
- Obtain hands-on review of the larger, centered layout. Passing tests and screenshots do not substitute for that review.

Instagram's unofficial routes and response shapes can change. This remains an experimental source release. The proposed friend journey is in [docs/UAT.md](docs/UAT.md).
