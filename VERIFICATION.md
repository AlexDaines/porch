# Verification

September 10, 2026. Xcode 26.6 / Swift 6.3.3, iOS 26.5 simulator, iPhone 17 Pro. The app targets iOS 18; iOS 18 and a physical phone have not been tested.

## Passing checks

The final offline Porch suite passed **8 test definitions / 24 expanded cases**, with no failures. Local result: `Test-Porch-2026.09.10_04-37-25--0400.xcresult`.

The production adapter ran in actual WebKit against synthetic responses. Checks covered positive following status, ads/paid partnerships, Reels, recommendation modules, a legitimate caption containing “Sponsored,” photo/video carousel data, deduplication, explicit pagination, story/thread ID membership, accepted inbox isolation, malformed schemas, login and rate-limit failures, GET-only requests and CDN URL restrictions. Login navigation checks covered exact HTTPS hosts, credential-bearing/spoofed URLs and encoded discovery routes.

The sample UI journey opened a story by tapping its row, advanced and closed it, switched between Feed/Stories/Messages, opened Settings, ended the session and returned to Welcome. Whole-row hit testing was fixed after this check found untappable blank space. The journey also exercised navigation at the largest accessibility text size. Visual inspection found crowding in the first fallback layout; the final layout gives the sample label and Settings their own row. Full-screen captures replaced app-only snapshots that omitted unchanged compositing layers. Public screenshots were visually inspected and contain only fictional sample content.

The final opt-in PorchAccountCheck suite passed **2 tests**, with no failures. Local result: `Test-PorchAccountCheck-2026.09.10_04-38-29--0400.xcresult`.

Using an existing signed-in account, that run returned **3 native Following posts, 1 followed story group with 1 media item, and 0 accepted inbox threads**, all without an adapter error. The story's video URL loaded through AVFoundation with `isPlayable == true`. Earlier probes also rendered four posts before the final exclusion rules were applied; counts are observations, not fixed acceptance expectations.

The signed-in UI test verified separate native Feed, Stories and inbox views, opened and closed the native story viewer, and asserted that no web view was present in the reading screens. The real post images and story preview were visually inspected. No follows, likes, posts, messages or seen-marker requests were performed. Signed-in screenshots and raw result bundles remain private and excluded from git.

Adapter syntax and `git diff --check` passed. Candidate source paths were reviewed and scanned for credential/private-account material. No build products, signing material, raw responses or live account images belong in the release.

## Explicit limits

- **Video playback is not verified.** A separate synchronous playback-time probe stalled in the simulator's MediaToolbox/CoreAudio locks. Its run was interrupted and recorded as unsuccessful. The replacement asynchronous asset check proves that the media loads as playable; it does not prove time progression, audio output or physical-device playback. The app uses native AVKit behind an explicit Play button.
- The live inbox was empty. Native conversation parsing/order is covered by synthetic fixtures; a populated live conversation has not been verified. Messages are read-only, capped to the most recent 20, and attachments are placeholders.
- Native pagination, mixed-media carousels and adversarial exclusions have fixture coverage; not every variant has live coverage. Unofficial Instagram routes and response experiments can change. Excluded or unknown content may be omitted.
- Existing sign-in was reused. A prior login-page check established reachability, but the rewritten sign-in sheet has not been re-tested from a freshly signed-out account, and challenge/2FA/alternate login flows are not fully verified.
- This is an experimental open-source app, not an App Store release or a claim of complete Instagram compatibility.
