# Porch constitution

Constitution ID: `porch`  
Version: **1.0.0**  
Adopted: **2026-09-13**  
Authority: the project owner's explicit direction, recorded in the adoption history below.

This is Porch's single canonical project constitution. The articles govern product decisions, implementation and constitutional review. [DESIGN.md](DESIGN.md) records current design choices and rationale; [AGENTS.md](AGENTS.md) carries implementation guidance; [VERIFICATION.md](VERIFICATION.md) records evidence and limitations. Those documents implement these commitments and may evolve without making a reviewer’s personal taste a constitutional rule. The constitution does not certify any current build as compliant or override a user's explicit instructions; a changed governing commitment must be recorded through PORCH-11.

## PORCH-01 — Purpose and restraint

Porch exists to help people who already know Instagram connect with people they choose, with less unwanted stimulation. Its success is the user's intended outcome, including intentionally stopping. More time, more scrolling, more content consumed or more actions cannot by themselves count as improvement. Separate content streams and deliberate access must support that purpose; engagement maximization must not become a competing objective.

## PORCH-02 — Informed consent, without shame

Porch must support informed consent, without shame. Choices must be understandable and voluntary, with their material effects clear before the action. Declining, stopping or changing one's mind must not invite guilt, punishment or pressure. Do not use streaks, fear of missing out, moral scores, coercive reminders, pressure timers or emotionally loaded failure/success cues to direct consumption. Do not claim therapeutic outcomes that have not been established.

## PORCH-03 — Factual, optional awareness

Usage-awareness features, such as histories, summaries, reminders or assessments of app use, must be optional and must not gate access to the core app. Feedback must describe what is actually measured, its scope and its limits; loaded posts must never be presented as posts read or seen. Saved usage histories, summaries and reminders require an explicit, reversible choice and local control. Immediate interaction status, such as the number of posts available after a chosen load, may accompany that action and must remain quiet factual feedback rather than a judgment, target or inferred attention measure. Do not introduce background behavioral analytics to support awareness.

## PORCH-04 — Deliberate loading and stopping

The user must control whether more feed content loads, whether a story advances and whether media plays. Opening or dismissing a choice must not perform it. A selected amount is a bound on the deliberate reveal; server uncertainty, partial results and technical limits must be described honestly. Do not silently chase pages, autoplay, advance stories automatically or use scrolling as permission for more content. Preserve the user's choice through retries and navigation. Cancellation and session closure must stop new dispatches and prevent stale work from repopulating an ended session; do not imply that an already-dispatched server action was undone. Stopping is a valid outcome and must remain easy.

## PORCH-05 — Free and open

Porch must remain free to use and open source. Do not add subscriptions, payment gates or advertising, or sell attention or personal data. Keep the source and the information needed to build it available under the repository's [open-source license](LICENSE). Do not exploit dependence or difficulty leaving to extract payment. Signing, platform availability and upstream limitations must be stated honestly; openness is not a promise that those constraints disappear.

## PORCH-06 — Privacy and user authority

Credentials and private content must stay under the user's control and be collected, retained and exposed only as needed for the requested function. Do not send private data to a Porch backend or add behavioral profiling. Diagnostics must be bounded, local and privacy-preserving; credentials, message bodies, direct account identifiers, identifying URLs and raw private responses must not enter diagnostic logs or public artifacts. Any diagnostic correlation must be purpose-limited and must not expose those identities. Export must be an explicit user action. Real sends and other consequential account actions require specific authorization; tests must use synthetic data unless the exact live action is authorized. Preserve user work, including drafts, before replacing a running app.

## PORCH-07 — Accessible restraint

Minimalism must preserve legibility, understandable controls and native accessibility. Support enlarged text, usable touch targets and accessible names without relying on color alone. Aesthetic restraint must not mean tiny text, hidden essential actions or loss of input/selection behavior. Evaluate reachability and comprehension on the rendered interface. Exact font sizes, shapes, palette values and layouts belong in design and task requirements, where they can be revised with evidence.

## PORCH-08 — Honest outcomes and evidence

Claims must match the evidence and its limits. Distinguish synthetic fixtures from live-account outcomes, a server acknowledgement from recipient delivery, an archive from an installed build, and installation from a successful launch. Never call an uncertain action successful or automatically retry a possibly completed send. Preserve failed, mixed and inconclusive results; repeated passing runs do not establish the cause of a failure. State unverified behavior and open limitations when handing off a build. Adopting or citing this constitution is not verification.

## PORCH-09 — Review against the pinned constitution

Before a constitutional review begins, record the constitution path, declared version, immutable Git commit containing it, and content hash; also pin the artifact/build under review and the review's scope. A version label or moving branch alone is insufficient. Each constitutional finding must identify the article ID, observed evidence, the reasoning connecting them, and its confidence or uncertainty. Use `conforms`, `violates` or `not established` for the assessed requirement; lack of evidence is not proof of conformity.

Taste or preferences outside the pinned articles are proposals, not constitutional violations. A separate explicit task requirement may support a task-contract finding, but must be named and cited separately. Do not invent engagement metrics, aesthetic ideals or a reviewer-specific definition of a good app as acceptance criteria. Retain disagreements and unresolved findings; a reviewer may recommend an amendment through PORCH-11 but may not silently rewrite the standard.

The charter's silence is not immunity from a substantiated correctness, security, safety, accessibility or explicit user-requirement issue. Report such findings under their actual authority with evidence, separately from constitutional findings. Missing constitutional coverage may justify a proposed amendment; it must not conceal the underlying issue or turn unsupported taste into a violation.

## PORCH-10 — Separate blind trials from constitutional review

Blind UI task participants must never receive this constitution, design rationale, staff guidance, reference paths or expected solutions. They receive only the sealed user task and permitted interface access. Run them in isolated contexts without automatic loading of this repository's instructions; do not ask an exposed participant to forget the material and continue as if blind. Record any exposure and invalidate the affected blinded claim.

Constitutional reviewers receive the pinned constitution separately from participants and assess the allowed evidence against its articles. Do not feed reviewer advice back into an active sealed participant trial. Intentional stopping cannot be relabeled as confusion, and extra consumption cannot improve a task's success score. Existing sealed trials retain their original contracts; any retrospective constitutional analysis must be separate and explicitly labeled.

## PORCH-11 — Amendments and review integrity

An amendment must state the affected article IDs, proposed text, reason, supporting evidence and expected effect on users. Normative amendments require explicit project-owner approval before adoption. Record that authority and the change in the adoption history, increment the version for every published revision, and keep article IDs stable; retire an ID explicitly rather than reusing it for another commitment.

Routine reversible implementation decisions that satisfy the commitments do not require constitutional approval. Existing explicit owner direction can authorize an amendment; record that direction rather than asking for the same permission again.

Seal the constitution revision, task, rubric and artifact before a review or trial begins. Do not change the constitution after seeing results to make that sealed review pass. An approved amendment applies to subsequent reviews under a new declared revision and seal; preserve the original finding and its original standard. Editorial corrections must also be versioned and must not disguise a normative change. Conflicts or ambiguities must be reported rather than resolved by a reviewer silently weakening an article.

## Adoption history

| Version | Date | Authority and change |
| --- | --- | --- |
| 1.0.0 | 2026-09-13 | Initial adoption requested by the project owner: make “informed consent, without shame” constitutional and ground adversarial review in a stable charter. Consolidates Porch's existing free/open, privacy, restraint, accessibility and truthful-verification commitments, together with the explicit review and participant-isolation requirements. |

The originating product rationale is preserved in [DESIGN.md](DESIGN.md): respect people familiar with Instagram, separate stimulation, and provide deliberate choices without a subscription funnel. Its concrete interface details remain design decisions. Build status and empirical results belong in [VERIFICATION.md](VERIFICATION.md) and their linked review records, not in the normative articles.
