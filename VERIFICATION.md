# Verification

September 10, 2026. Porch **0.2 (5)**. Xcode 26.6 / Swift 6.3.3. Deployment target iOS 18; iOS 18 itself has not been tested.

## Simulator regression

The offline Porch suite passed **22 test definitions / 38 expanded cases**, with no failures, on iPhone 17 Pro / iOS 26.5. Local result: `Test-Porch-2026.09.10_13-34-00--0400.xcresult`.

Build 5 applies the user's sharp-corner rule to swatches, selection outlines, story avatars, play-button backgrounds and app sheets. Settings uses a plain header and confirmations appear inline. The introduction, largest-text introduction, expanded color settings, stories, sample conversation, clear-sign-in confirmation and fictional native composer were visually inspected. The existing UI journeys now also verify that cancelling sign-in clearing retains the session, and cancelling the unresolved-send confirmation preserves the draft and send block. Only fictional transport was used for sending checks. [Color settings screenshot](docs/images/color-settings.png).

The color introduction journey verifies first launch without a web view, selecting Mist, continuing, changing to Lilac in Settings, persistence through restart, no repeated introduction, all five swatches at the largest accessibility text size and continuing with the default color. The introduction, colored sample feed and expanded Settings were visually inspected. An inherited accessibility identifier initially shadowed the Settings swatch identifiers; removing it and querying the visible disclosure label resolved the failed test. A duplicate selected-color label in expanded Settings was removed after visual review.

A startup capture revealed the system's default white launch screen before the dark introduction. Build 4 adds an explicit black launch color asset and dark appearance. A subsequent capture during launch shows a black app surface; the settled first-launch screen remains the color picker. The Release Info.plist and compiled asset catalog were checked as well.

The production adapter runs in actual WebKit with synthetic responses. Coverage includes Following-only filtering, paid partnerships/ads, Reels/recommendation exclusions, malformed schemas, restricted media URLs, explicit feed/inbox/thread pagination, accepted and opened recipient membership, sender alignment, bounded text encoding, acknowledgement validation, duplicate-send prevention and rate limits. These tests never send real messages.

Client-state tests cover retained content after failed refresh/pagination, per-tab error isolation, late responses after session closure, the unresolved-send journal across restart, validation, duplicate taps and server-directed cooldown. The journal test proves that message bodies are absent from persisted attempt records.

The fictional UI journeys cover separate navigation, large-text navigation, session finish, failed refresh with retained content, the native keyboard/composer, acknowledged sending, disabled repeat sends and reconciliation after an uncertain result. The final fictional composer screenshot was visually inspected and is published in `docs/images/fictional-composer.png`.

Native AVPlayer tests prove time progression with a generated local video, stopping/releasing the player, and recovery from an invalid asset without a permanent spinner.

## Read-only Instagram integration

On build 2, the opt-in PorchAccountCheck suite passed **2 tests**, with no failures, on iPhone 17 Pro / iOS 26.5. Local result: `Test-PorchAccountCheck-2026.09.10_12-47-40--0400.xcresult`. The appearance changes did not exercise the live account again.

The existing signed-in account returned **3 Following posts, 1 followed story group containing 1 media item, and 0 accepted inbox threads**, with no adapter error. A real Instagram video loaded as playable and advanced at least 0.75 seconds through AVPlayer's asynchronous time observer. This replaces the earlier unsuccessful synchronous playback probe; audio output is not established by this muted check.

The UI journey opens and closes a story, switches among separate native Feed, Stories and inbox views, and verifies that reading screens contain no web view. Real media rendering was inspected privately. An earlier UI assertion expected every story preview to be an accessibility Image; the video preview exposes a Play button. The corrected assertion accepts the photo or actionable video preview. No follows, likes, posts, messages or seen-marker requests were performed. Private account screenshots and raw result bundles remain excluded from git.

The fresh, signed-out PorchLiveCheck passed **1 test** on a separate iPhone 17e / iOS 26.5 simulator. It verified Instagram's login page and secure password field without entering credentials or disturbing the signed-in simulator. Local result: `Test-PorchLiveCheck-2026.09.10_12-40-39--0400.xcresult`. This proves form reachability, not completion of login, challenges or 2FA.

## Physical device and Release

Build 2 was signed, installed and launched on the paired iPhone 14 Pro Max. That physical-device suite passed **4 tests**: both local playback tests and both fictional composer/recovery UI journeys. Private result: `artifacts/private/uat-device.xcresult`. These checks use no Instagram requests and establish neither live delivery nor account login on the phone.

Builds 3 and 4 were signed and installed on the same phone. Launch was refused because the phone was locked, so the new introduction has simulator interaction evidence only. The local install helper initially selected an XCTest runner left in the build directory. Its application selection was corrected and fixture-tested to exclude test runners and refuse ambiguous app products; the subsequent installs selected `dev.alex.porch` correctly.

Build 5 was signed, installed and successfully launched on that iPhone. Its appearance was inspected in the simulator; no additional physical-device account or interaction checks were performed.

`bash tools/build-uat.sh` successfully produced the unsigned device Release archive at `.build-uat/Porch.xcarchive`. The application reports version 0.2 / build 5 and is an arm64 device executable. The compiled Release binary excludes the appearance-reset and appearance-fixture flags, the DM fixture flag and the fixture transport symbol. Distribution and signing of this archive belong to the operator's own installation workflow.

## Remaining acceptance

- A populated real conversation, one explicitly authorized text send and a received reply remain unverified. Fixture acknowledgements are not delivery evidence. Sending is limited to existing accepted conversations; non-text attachments are descriptive placeholders.
- Complete account login/challenge/2FA on the physical phone, audible video, live background/foreground behavior, and installation through the chosen homegrown Release workflow remain to be accepted.
- Pagination and mixed-media variants have fixture coverage, not exhaustive live coverage. Instagram's unofficial routes and experiments may change or reject requests. Excluded or unknown content may be omitted.
- This is an experimental source release. These passing checks do not establish production readiness or full Instagram compatibility. The friend testing journey is in [docs/UAT.md](docs/UAT.md).
