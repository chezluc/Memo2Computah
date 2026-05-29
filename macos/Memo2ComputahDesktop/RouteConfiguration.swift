import Foundation

struct RouteConfiguration: Codable {
    var version: Int
    var routes: [RouteDefinition]

    static let defaultConfiguration = RouteConfiguration(
        version: 1,
        routes: [
            RouteDefinition(id: "automatic", label: "Auto", kind: "automatic", target: nil, shortcut: nil),
            RouteDefinition(id: "clipboard", label: "Clipboard", kind: "clipboard", target: nil, shortcut: nil),
            RouteDefinition(id: "codex", label: "Codex", kind: "app", target: "Codex", shortcut: nil),
            RouteDefinition(id: "plexi", label: "Plexi", kind: "app", target: "Plexi", shortcut: nil),
            RouteDefinition(id: "chrome", label: "Google Chrome", kind: "app", target: "Google Chrome", shortcut: nil),
            RouteDefinition(id: "iawriter", label: "iA Writer", kind: "app", target: "iA Writer", shortcut: nil),
            RouteDefinition(id: "textedit", label: "TextEdit", kind: "app", target: "TextEdit", shortcut: nil),
            RouteDefinition(id: "terminal", label: "Terminal", kind: "app", target: "Terminal", shortcut: nil),
            RouteDefinition(id: "iterm", label: "iTerm", kind: "tmux", target: "voice_return", shortcut: nil),
            RouteDefinition(id: "iterm:1", label: "iTerm 1", kind: "tmux", target: "voice_return", shortcut: "1"),
            RouteDefinition(id: "iterm:2", label: "iTerm 2", kind: "tmux", target: "voice_return", shortcut: "2"),
            RouteDefinition(id: "iterm:3", label: "iTerm 3", kind: "tmux", target: "voice_return", shortcut: "3"),
            RouteDefinition(id: "iterm:4", label: "iTerm 4", kind: "tmux", target: "voice_return", shortcut: "4"),
            RouteDefinition(id: "wezterm", label: "WezTerm", kind: "tmux", target: "voice_return", shortcut: nil),
            RouteDefinition(id: "kitty", label: "Kitty", kind: "tmux", target: "voice_return", shortcut: nil),
            RouteDefinition(id: "tabby", label: "Tabby", kind: "tmux", target: "voice_return", shortcut: nil)
        ]
    )
}

struct RouteDefinition: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var kind: String
    var target: String?
    var shortcut: String?

    static func newAppRoute(number: Int) -> RouteDefinition {
        RouteDefinition(
            id: "custom-\(number)",
            label: "New Route \(number)",
            kind: "app",
            target: "",
            shortcut: nil
        )
    }
}
