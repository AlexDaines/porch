import Foundation

enum NavigationPolicy {
    enum Decision: Equatable { case allow, blockedSurface, external, invalid }
    static let hosts: Set<String> = ["instagram.com", "www.instagram.com"]
    static let login = URL(string: "https://www.instagram.com/accounts/login/")!

    static func classify(_ url: URL) -> Decision {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return .invalid }
        guard hosts.contains(host) else { return .external }
        var path = url.path.lowercased()
        for _ in 0..<3 { path = path.removingPercentEncoding ?? path }
        let parts = path.split(separator: "/").map(String.init)
        if parts.contains(where: { ["reel", "reels", "explore", "tv"].contains($0) }) { return .blockedSurface }
        return .allow
    }

}
