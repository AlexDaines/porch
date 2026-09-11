# Local diagnostics

Build 9 records diagnostics in Release as well as Debug. Settings → Diagnostics shows storage health and the latest failure. **Share log** produces `Porch-diagnostics.json` and opens the iOS share sheet. No automatic upload, analytics service, remote endpoint or Porch account is involved.

## Following a failed send

1. Find `sendPrepared` and its `attempt_id`. `thread_ref` and `context_ref` are installation-keyed HMACs; they reveal neither the conversation ID nor the outgoing message context.
2. Join `context_ref` to `requestQueued`, then follow its `request_id` through `requestStarted` and `adapterStage`. Stages show validation, fetch start, HTTP arrival, decode, receipt and completion. An HTTP result can be recorded before parsing fails.
3. Read `http`, the fixed `reason` and `result`, request/response sizes, timings, CSRF/viewer presence, response shape and receipt-match flags. `response_shape` contains allowlisted field names and types only. `server_fingerprint` groups identical unknown server errors within one installation without exporting their text.
4. Follow `sendReceipt`, `sendRefused` or `sendUnconfirmed`. After an exit, `sendRestored` and `sendReconciled` retain the attempt correlation. A receipt means acknowledged by Instagram, not delivered or read. Logging never sends or retries a message.

Every report includes the current app/build, iOS version and hardware family even when the launch event has rotated out. Every event has a wall-clock timestamp (milliseconds since Unix epoch), monotonic process uptime, process session UUID and sequence. Request timing fields are milliseconds. `bridge_ms` measures the full JavaScript call; it includes fetch and decode time, so these durations must not be summed. `raw_count` and `filtered_count` describe one bounded response. Correlation references persist across app updates while the local key remains available; reinstalling or losing its protected key changes them.

## Coverage

| Area | Recorded metadata |
| --- | --- |
| App | Version/build, iOS version, hardware family, lifecycle, low-power/thermal state, memory warnings |
| Network | Availability, interface category, constrained/expensive status, IPv4/IPv6/DNS capability; no IPs, SSIDs or endpoints |
| Sign-in | User entry/cancellation, local session hint, verification result, suppressed checks, navigation category, HTTP status, page failures, cookie-change event without cookie values |
| Transport | Queue depth/delay, generation, WebKit preparation/failure/termination, request stages, sizes, duration, outcome, bounded model counts |
| Messages | Input length, membership/context validation flags, prepared/dispatched attempt, receipt matching, rejection, uncertainty and reconciliation |
| Media | Start/readiness/first playback/stop/failure; keyed URL reference, timing and known error domain/code with bounded underlying error codes; no per-frame event stream |
| iOS diagnostics | MetricKit crash, hang, CPU, disk and launch diagnostics with at most 64 binary UUID/offset frames; payload time range and originating app version |

MetricKit delivery is controlled by iOS and can be delayed or absent, especially under a debugger. The log does not intercept signals or claim to capture every crash, force-quit or memory termination. Binary coordinates require matching archived dSYMs for symbolication; preserve the release archive used for distribution. Crash exception descriptions, raw MetricKit payloads and register contents are deliberately excluded.

## Storage and privacy contract

`Sources/DiagnosticsLog.swift` defines the sole logging schema. Arbitrary message, URL, error description and response-body APIs do not exist. Unknown keys or values are dropped. The adapter's progress messages are accepted only from the isolated app content world and the currently active request. A second sanitizer runs when loading files for export, including older or damaged entries.

Trace files live in Application Support, with ten rotating 2 MiB segments and a 14-day retention window. One sanitized, replaceable JSON export is stored separately and expires 14 days after creation; total disk usage can exceed the 20 MiB trace budget. Retention is enforced when the app records or reads logs. Copies shared outside Porch are controlled by their recipient. All directories are excluded from backup; directories use mode 0700, files 0600 and iOS protection until the first unlock after boot. The per-installation HMAC key never enters a report or an Instagram request. Debug fixtures use a separate directory.

Writes run on a serial utility queue and synchronize each complete JSONL entry. The prepared send trace is flushed before passing the send to the transport; another generation/cancellation check prevents a closed session from dispatching after that wait. Abrupt termination may still lose the final pending events. Truncated lines and oversized damaged files are skipped, counted and reported; they cannot inject arbitrary fields into an export.

Storage failures cannot throw from `record` or trigger network activity. Failed writes retain at most 512 sanitized entries in memory for the current process, and the report shows `writeFailures`, `unreadableLines` and `directoryAvailable`. Export and deletion errors appear on the Diagnostics screen. A memory fallback cannot survive process termination. Clear log deletes trace segments, the fallback and the prior export; it leaves the installation key, sign-in and unresolved-send journal intact, then records the clearing event.

Reports exclude credentials and content, but still contain activity times, message lengths, device/build information and stable pseudonymous correlations. Share them deliberately. Nothing here reconstructs a failure from a build that did not yet record durable diagnostics.
