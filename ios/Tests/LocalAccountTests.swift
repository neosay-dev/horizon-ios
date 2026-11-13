import Foundation

/// Run with LocalAccount.swift; no app, simulator or Microsoft configuration is needed.
@main
struct LocalAccountTests {
    static func main() {
        for name in ["abc", "Player_01", String(repeating: "a", count: 16)] {
            precondition(LocalAccount.normalizedName(name) == name, "Valid name rejected: \(name)")
        }
        precondition(LocalAccount.normalizedName(" \nSteve_42\t ") == "Steve_42")
        for name in ["", " ", "ab", String(repeating: "a", count: 17),
                     "two words", "a-b", "a.b", "a\nb", "Игрок", "abc🎮", "ＡＢＣ"] {
            precondition(LocalAccount.normalizedName(name) == nil, "Invalid name accepted: \(name)")
        }
        precondition(LocalAccount.launchArguments(name: "Steve_42") == ["--name", "Steve_42"],
                     "Local launch must pass the name without an authenticated session")
        print("Local account tests passed")
    }
}
