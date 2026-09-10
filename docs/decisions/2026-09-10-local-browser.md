# Superseded: local browser filtering

The initial prototype loaded Instagram's website and removed recognized unwanted DOM elements. It incorrectly treated the absence of a supported consumer API as a reason not to test native rendering. The user challenged that assumption, and a live authenticated data experiment succeeded.

The final architecture is recorded in [native-data-client](2026-09-10-native-data-client.md). Browser rendering now serves only sign-in.

The standalone repository remains deliberate: publishing this app must not publish the user's private multi-app atelier. MPL-2.0 is the source license; free access is project policy.
