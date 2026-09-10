# Porch 0.2 UAT

This build is for testing the native reading and messaging flows. It is not a claim of full Instagram compatibility. Installation is handled by the operator's existing workflow. See [VERIFICATION.md](../VERIFICATION.md) for observed evidence and remaining acceptance gates.

## Internal acceptance before inviting friends

- Verify a real, authorized text send and a reply in a populated conversation. The composer and failure handling have fixture coverage; that is not live delivery evidence.
- Verify on a physical iPhone: fresh login, an account challenge/2FA flow when applicable, media playback with sound, background/foreground, and the keyboard/composer.
- Confirm the Release build installs through the chosen distribution workflow.

## Friend testing journey

On first launch, choose a color or continue with Sage. Reopen Porch and confirm the introduction stays completed. In Settings → Color, change the accent and check it remains selected after restarting.

1. Sign in through Instagram. Close and reopen Porch, then use Open Instagram without re-entering credentials. Clear sign-in when finished; that removes local session data.
2. Open Feed. Check that it contains followed posts and has no story tray, Reels or suggested modules. Swipe a carousel. Tap Play on a video; backgrounding or leaving the view should stop it.
3. Open Stories. Choose a person, advance and close manually. Stories should not advance themselves or reveal Feed underneath the content area.
4. Open an existing conversation. Check sender names, load earlier messages, send one agreed test message, and compare the result with Instagram. Sent means acknowledged, not read or delivered.
5. Turn off connectivity after loading content. Refresh: existing content should remain with an error. Restore connectivity and retry. For an uncertain DM send, check the conversation before allowing another message; no automatic resend should occur.
6. Try landscape and larger text. Navigation, close controls, media and the message composer should remain reachable.

## Reporting a problem

Include the app/build version, iPhone model, what you did, expected result and actual result. Settings → Share diagnostic details supplies a report with version and request status only. Avoid putting private screenshots, usernames, messages, cookies or raw responses in public GitHub issues. The diagnostic report does not include those fields.

## Current boundaries

Text replies are supported in existing accepted conversations. Starting a new conversation, pending message requests, media attachments, voice messages, reactions, typing indicators, push notifications and read receipts are outside this UAT build. Attachments are labelled, not silently rendered as empty messages. Explicit pagination is bounded to 200 records per view/session. Reload starts a new batch. Unofficial Instagram routes may reject requests or change their format.
