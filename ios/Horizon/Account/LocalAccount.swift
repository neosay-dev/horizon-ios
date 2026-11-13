import Foundation

/// The engine derives its offline UUID from this name; no access token is involved.
enum LocalAccount {
    static func normalizedName(_ input: String) -> String? {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...16).contains(name.utf8.count),
              name.utf8.allSatisfy({ byte in
                  (65...90).contains(byte) || (97...122).contains(byte)
                      || (48...57).contains(byte) || byte == 95
              }) else { return nil }
        return name
    }

    static func launchArguments(name: String) -> [String] {
        ["--name", name]
    }
}
