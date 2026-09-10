# Plural is the Horse Weapons reference

The user identified Plural, the moped travel-time app, as the Horse Weapons reference after rejecting visual noise, explanatory copy and a clunky navigation bar. Its actual `Theme.swift`, `ContentView.swift` and rendered glance screen informed this revision.

The earlier monochrome revision incorrectly inferred that the Light Phone reference meant removing lime. That was an implementation inference, not a user requirement. The user's clarification supersedes it.

## Tokens and layout

- Canvas: `#000000`; text: `#E9E4D6`; secondary text: `#8A8375`; rules: `#26231F`; active controls: `#B6F23C`.
- System monospaced semibold utility labels, with restrained tracking. System sans-serif names and captions.
- Left-aligned content, 20-point text margins, thin rules between entries. Photos remain the principal visual element.
- One top control row. The active destination uses lime text and a 32-point underline, matching Plural's mode selector. Large text stacks the destinations so labels remain whole.

Plural's large route metric serves its specific task; Porch does not invent a metric or prominent heading to imitate it. Feed and Stories remain separate, with no story tray in Feed. Settings holds secondary tools and an initially collapsed About disclosure. The same styling applies to real native content and the clearly identified offline sample.

Existing clients establish useful prior art: [SocialLite's product page](https://apps.apple.com/us/app/sociallite-block-reels-shorts/id6757661674) describes filtering distracting content while retaining social features; [OpenSocials](https://github.com/liamperritt/opensocials) publishes a minimal social-browser implementation. Their existence is evidence of feasible products, not proof of a particular internal architecture. Porch's data path is documented and tested independently in [DESIGN.md](../../DESIGN.md) and [VERIFICATION.md](../../VERIFICATION.md).
