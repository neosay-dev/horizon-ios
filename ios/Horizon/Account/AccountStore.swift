import Foundation
import UIKit

/// The signed-in Microsoft account. Play needs one that owns Minecraft: Java Edition
/// (docs/microsoft-account.md, "The owner gate"); there are no offline names.
@MainActor
final class AccountStore: ObservableObject {
    enum State: Equatable {
        case signedOut
        case code(userCode: String, url: URL)
        case working
        case signedIn(name: String)
    }

    @Published private(set) var state: State = .signedOut
    @Published var error: String?

    private var tokens: MicrosoftAuth.MicrosoftTokens?
    private var session: MicrosoftAuth.Session?
    private var signIn: Task<Void, Never>?

    init() {
        if let data = Keychain.load("microsoft"),
           let saved = try? JSONDecoder().decode(MicrosoftAuth.MicrosoftTokens.self, from: data) {
            tokens = saved
            if let data = Keychain.load("session"),
               let s = try? JSONDecoder().decode(MicrosoftAuth.Session.self, from: data) {
                session = s
                state = .signedIn(name: s.name)
            }
        }
    }

    var configured: Bool { MicrosoftAuth.clientID != nil }

    func startSignIn() {
        error = nil
        signIn?.cancel()
        signIn = Task {
            do {
                state = .working
                let code = try await MicrosoftAuth.deviceCode()
                state = .code(userCode: code.user_code, url: URL(string: code.verification_uri)!)
                UIPasteboard.general.string = code.user_code
                let ms = try await MicrosoftAuth.poll(code)
                state = .working
                try await finish(ms)
            } catch is CancellationError {
                state = session.map { .signedIn(name: $0.name) } ?? .signedOut
            } catch {
                self.error = error.localizedDescription
                state = .signedOut
            }
        }
    }

    func cancelSignIn() { signIn?.cancel() }

    func signOut() {
        Keychain.delete("microsoft")
        Keychain.delete("session")
        tokens = nil
        session = nil
        state = .signedOut
    }

    private func finish(_ ms: MicrosoftAuth.MicrosoftTokens) async throws {
        let s = try await MicrosoftAuth.minecraft(ms.accessToken)
        tokens = ms
        session = s
        if let data = try? JSONEncoder().encode(ms) { Keychain.save(data, for: "microsoft") }
        if let data = try? JSONEncoder().encode(s) { Keychain.save(data, for: "session") }
        state = .signedIn(name: s.name)
    }

    /// A fresh session for Play, asked again of the Minecraft services, so ownership is current.
    func sessionForPlay() async throws -> MicrosoftAuth.Session {
        guard var ms = tokens else { throw MicrosoftAuth.AuthError.doesNotOwn }
        if let s = session, s.expires > Date() {
            return s
        }
        state = .working
        do {
            ms = try await MicrosoftAuth.refresh(ms)
            try await finish(ms)
        } catch {
            state = session.map { .signedIn(name: $0.name) } ?? .signedOut
            throw error
        }
        guard let s = session else { throw MicrosoftAuth.AuthError.doesNotOwn }
        return s
    }

    /// The game's `--session-file`: read once and deleted by the game; owner-only.
    static func writeSessionFile(_ s: MicrosoftAuth.Session) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("horizon-session.json")
        var json: [String: Any] = ["name": s.name, "uuid": s.uuid, "access_token": s.accessToken, "user_type": "msa"]
        if let xuid = s.xuid { json["xuid"] = xuid }
        let data = try JSONSerialization.data(withJSONObject: json)
        try? FileManager.default.removeItem(at: url)
        FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
        return url
    }
}
