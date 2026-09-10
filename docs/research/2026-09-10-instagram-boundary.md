# Integration references

Observed September 10, 2026. Protocol observations are not promises of platform support.

- The [FeurStagram source notes](https://github.com/jean-voila/FeurStagram/blob/main/Readme.md) identify `pagination_source=following` on the timeline request. Porch independently verified the request against an existing session and inspected the response's source and following flags.
- [Instaloader's context implementation](https://github.com/instaloader/instaloader/blob/master/instaloader/instaloadercontext.py) documents the web application's public app ID and request headers. These are protocol constants, not credentials.
- [Instagrapi's direct implementation](https://github.com/subzeroid/instagrapi/blob/master/instagrapi/mixins/direct.py) exposes the inbox/thread data contract. Porch uses only read routes and does not adopt a password-based login library.
- Apple's [WKContentWorld](https://developer.apple.com/documentation/webkit/wkcontentworld) defines separate JavaScript worlds. The data transport uses an empty document and the app's content world, with website JavaScript disabled.
- Apple's [app-bound navigation](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/limitsnavigationstoappbounddomains) limits the WebKit context; Porch also validates exact HTTPS login hosts and CDN media URLs.
- Meta's [official Instagram collection](https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api) describes professional-account integrations. It is not the consumer Following-feed route used here.

No implementation code from these projects is bundled. Porch's adapter was written for its bounded native models. A successful local source release does not establish App Store eligibility or long-term Instagram compatibility.
