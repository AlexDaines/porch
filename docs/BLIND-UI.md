# Offline Blind UI fixture

`PorchBlindUI` is a separate Debug app (`dev.alex.porch.blindui`) for locally
recorded interface trials. It does not establish live Instagram delivery or
human usability. Runtime/participant qualification, the observed staff reference,
five fresh trials, network fencing, and independent scoring belong to the
[Blind UI project](/Users/alex/dev/personal/blind-ui).

## Shared interface and declared differences

The fixture uses the same `ContentView`, native Feed/Stories/Messages tabs,
inbox rows, conversation sheet, text input, send button, acknowledgement,
uncertainty/reconciliation, and accepted-thread client journal as Porch. There
are no participant instructions or study identities in the interface. The
normal `Sent` text is used; it is never itself the outcome oracle.

Differences are restricted to the dedicated `BLIND_UI_FIXTURE` target:

- Start on Feed, with the introduction completed and Sage selected. Six accepted
  conversations are available in fixed order: Maya, Weekend plans, Leo, Mom,
  Aunt Linda, Moped rides. Mom is the fourth row, thread `8104`, sink identity
  `fixture-mom-001`. Accepted inbox membership and opening the thread are both
  required by the synthetic transport. Creating a new recipient is unsupported.
- All data is fixed synthetic content. One locally drawn illustration occupies
  the normal feed photo surface. Story data is also local. There are no remote
  image/video requests and no simulated network delay.
- Authentication connect, WebKit execution, remote photo loading and video
  playback are compile-disabled. Invalid launch configuration fails closed.
  Source-code navigation and diagnostic sharing are disabled in this build.
  These controls and login are outside this study's usability condition.
- Sink and recorder-file polling exist only in Debug. The ordinary Porch target
  cannot enable this fixture through launch arguments. Building the dedicated
  target as Release fails compilation. Production Release contains none of the
  fixture implementation or synthetic conversation data.

The build number remains the underlying Porch version; always identify this
artifact by bundle ID plus a digest of **all** app-bundle files, not the version
number or executable alone. Xcode Debug uses a separate `.debug.dylib`.

If the recorder freezes that bundle by removing write permissions, create a
separate installation copy before using `simctl install`. CoreSimulator can
fail with EACCES while staging a read-only `.app`. Restore directories to `0755`,
ordinary files to `0644`, and the main executable, `.debug.dylib`, and
`__preview.dylib` to their original `0755` mode. Keep the copy's enclosing evidence
directory at `0700`. Verify every file's bytes against the sealed manifest before
installation and against the installed bundle afterwards. Retain the untouched
frozen source. A content digest does not include permissions unless its manifest
explicitly says so.

## Launch and reset

Build with XcodeGen and the existing iOS workflow:

```sh
xcodegen generate
~/.claude/scripts/ios.sh build . PorchBlindUI 'Porch Blind UI Builder'
```

Install the resulting `.build-ios/Build/Products/Debug-iphonesimulator/PorchBlindUI.app`
on the recorder's separately owned simulator. Launch with:

```text
--blind-ui-fixture --blind-ui-run-id <UUID>
```

A **fresh lowercase run UUID** resets every study condition: appearance defaults,
pending-send journal, synthetic accepted writes and recorder context. The
run directory is `Library/Application Support/PorchBlindUI/<lowercase-UUID>/`
inside the app's data container. `configuration.json` records the selected
control. Reusing an interrupted run preserves accepted writes and the journal,
but invalidates study completion. No relaunch automatically sends or resets.
A previously closed run refuses new acceptance. Never reuse a run ID for a new
participant. Retain old run directories as staff evidence; do not hand them to
participants.

The staff helper `tools/blind-ui-container.py` locates a run, applies context,
closes recording, and verifies the local receipt. It has no UI driver or send
operation. A new UUID is the supported reset; there is no destructive reset flag.

## Action context and independent close

The recorder atomically writes `action-context.json` before each input:

```json
{"schema":"blind-ui/action-context-v1","run_id":"<run UUID>","action_id":"<action UUID>","broker_sequence":1}
```

Sequence is a positive, strictly increasing integer (maximum 100,000). Action
IDs are unique UUIDs. Wait for matching `action-context-ack.json` before issuing
one input. Its schema is `blind-ui/action-context-ack-v1` with the same three
identity/sequence fields. A 100 ms asynchronous poll reads at most 4 KiB per
control file on a utility task. The context is applied before acknowledging it.
There is no input retry in the app. The broker also must never repeat an
uncertain tap or send.

`run_id`, `action_id` and `broker_sequence` extend the existing closed
`DiagnosticsLog` schema. `actionApplied` identifies the handshake. Ambient
callbacks carry the active context, which is temporal association, **not causal
proof**. A send captures the action synchronously at the button, before its
async task; `sendPrepared`, `sendDispatched`, fixture request and receipt share
the original action plus `attempt_id`. The private attempt journal links that
attempt to sink-issued write IDs. New `viewState` events describe logical
Feed/Stories/Messages/Conversation/Story/Settings/Diagnostics state, visibility,
loading, sending, acknowledgement, error and draft validity transitions. No
view label, username or message text enters diagnostics. Screenshots/video,
not logical view events, establish observed pixels and transient confirmation.

At the end, the recorder writes `control.json`:

```json
{"schema":"blind-ui/control-v1","run_id":"<run UUID>","command":"close","command_id":"<command UUID>"}
```

Closing stops new fixture acceptance, waits for the native send operation to
settle, flushes and checks diagnostics, and atomically persists the sink and
`closed.json`. The latter has exactly `schema: blind-ui/closed-v1`, `run_id`,
`command_id`, `complete` (boolean). Require a matching command acknowledgement
**and** `sink.complete == true`. Close is staff work outside participant action
counts. `fixtureClosed` records its log boundary. Malformed context/control,
missing/corrupt storage, uncorrelated attempts, cleared diagnostics, overflow or interrupted launch
makes completion false or leaves no usable acknowledgement. A missing acknowledgement is invalid evidence.

The recorder must preserve both exact files before classifying or rejecting the
run. Require both complete flags to be true, the sink and close run IDs to match
the sealed run, and the close command ID to match the command just issued. A
false or stale close receipt invalidates the run even when the sink says true;
retain that failed evidence rather than repairing flags or discarding it. This
is a recording-integrity failure, not a measured user-interface failure.

## Accepted writes and controls

`sink.json` starts with `complete: false`. Its exact shape is:

```json
{"schema":"blind-ui/sink-v1","run_id":"<run UUID>","complete":false,"writes":[{"write_id":"<unique UUID>","recipient":"fixture-mom-001","text":"Thinking of you. How is your day?"}]}
```

Only committed synthetic acceptance enters `writes`. Rejected/uncertain
attempts appear separately in `attempts.jsonl`, including run, captured action,
attempt UUID, synthetic recipient, message length, result and accepted write
IDs. The exact synthetic message exists only in the sink; attempts and normal
diagnostics omit it. The sink is independent of optimistic bubbles, `Sent`,
or participant claims. This is a local fixture oracle, not an external
messaging service or tamper-resistant boundary against the recorder's OS user.

Staff-only launch argument `--blind-ui-control <mode>` selects one condition:

| Mode | Committed outcome | Native response |
| --- | --- | --- |
| `accepted` (default) | One write to selected recipient with entered text | Acknowledged |
| `rejected` | No write | Explicit restriction, draft retained |
| `accepted-unconfirmed` | One write | Uncertain; another send remains blocked until checked |
| `wrong-recipient` | One write to Aunt Linda | Acknowledged |
| `wrong-text` | One write with “See you soon.” | Acknowledged |
| `duplicate` | Two writes with distinct IDs | Acknowledged |
| `false-success` | No write | Acknowledged |

The last four intentionally make UI acknowledgement insufficient and qualify
independent outcome verification. They are different conditions, never mixed
silently into the normal cohort. Real wrong-recipient/text choices are also
observable in the ordinary fixture without fault injection.

## Durability, privacy and bounds

Sink/journal commits serialize and synchronize before returning acceptance.
Atomic replacement plus file and parent-directory fsync precedes a successful
close. These are two separately atomic files, not one atomic transaction: an
IO failure after the sink write may leave `sink.complete == true` on disk with
no matching close receipt. That is invalid evidence. Always require both files
and their matching identities, even if the app's in-memory failure flag is no
longer available. A crash before recorder close leaves incomplete evidence. Relaunch
preserves available state but never declares that an interrupted study was
lossless. UI acknowledgement is unaffected by evidence IO failure: the study
becomes invalid while the app remains usable.

Each run permits at most 256 stored attempts and 256 accepted writes, with the
native 1,000 UTF-16-unit text bound. Overflow permanently invalidates completion
and stops accumulating evidence; it does not retry or change business response.
Sink reads are capped at 2 MiB; journal reads at 1 MiB. Per-run diagnostics retain
the existing ten 2 MiB segments and 14-day retention. Raw study directories have
no automatic eviction: the recorder must retain or remove entire completed
runs under its evidence-retention policy. Their cumulative storage is not
bounded by the per-run cap.

Directories are mode 0700, evidence files 0600, excluded from backup, with
protection until first unlock. Synthetic sinks and screenshots remain in
`artifacts/private` or the recorder's private run directories, never Git or CI
uploads. Never copy `Diagnostics/redaction.key` into a report or recording;
only sanitized JSONL/exported diagnostics may be collected. Keep fixture proof
separate from model qualification and blind results.

## Regression evidence

`Tests/BlindUIFixtureTests.swift` verifies all control outcomes, opened-thread
validation, correlation across async dispatch, exact sink schema, privacy,
permissions, interrupted/closed runs, storage failure and bounds. It also
prints a measured 32-commit timing sample; this is host-specific instrumentation
cost, not a user-facing latency estimate. `BlindUITests` uses known selectors
to verify the shared composer, distractors, fresh reset and uncertain-send
reconciliation. Its screenshots/actions are staff regression evidence, never a
blind participant or the reference action count. Verify context/close on the
actual compiled app before freezing the reference artifact.
