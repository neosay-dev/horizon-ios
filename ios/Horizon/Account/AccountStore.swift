import Foundation
import Combine
import UIKit

/// A local profile or a signed-in Microsoft account. Local play uses only `--name`.
@MainActor
final class AccountStore: ObservableObject {
    enum State: Equatable {
        case signedOut
        case code(userCode: String, url: URL)
        case working
        case signedIn(name: String)
        case local(name: String)
    }

    @Published private(set) var state: State = .signedOut
    @Published var error: String?

    private static let localNameKey = "horizon.localAccountName"
    private let defaults: UserDefaults

    var hasAccount: Bool {
        switch state {
        case .signedIn, .local: return true
        default: return false
        }
    }

    private var tokens: MicrosoftAuth.MicrosoftTokens?
    private var session: MicrosoftAuth.Session?
    private var signIn: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: Self.localNameKey),
           let name = LocalAccount.normalizedName(stored) {
            state = .local(name: name)
            return
        }
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

    @discardableResult
    func signInLocally(name: String) -> Bool {
        guard let name = LocalAccount.normalizedName(name) else {
            error = String(localized: "Ник должен содержать от 3 до 16 символов: латинские буквы, цифры или подчёркивание.")
            return false
        }
        signIn?.cancel()
        defaults.set(name, forKey: Self.localNameKey)
        error = nil
        state = .local(name: name)
        return true
    }

    func startSignIn() {
        error = nil
        signIn?.cancel()
        signIn = Task {
            do {
                try Task.checkCancellation()
                state = .working
                let code = try await MicrosoftAuth.deviceCode()
                try Task.checkCancellation()
                state = .code(userCode: code.user_code, url: URL(string: code.verification_uri)!)
                UIPasteboard.general.string = code.user_code
                let ms = try await MicrosoftAuth.poll(code)
                try Task.checkCancellation()
                state = .working
                try await finish(ms)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                state = .signedOut
            }
        }
    }

    func cancelSignIn() {
        signIn?.cancel()
        switch state {
        case .code, .working:
            state = session.map { .signedIn(name: $0.name) } ?? .signedOut
        default: break
        }
    }

    func signOut() {
        signIn?.cancel()
        defaults.removeObject(forKey: Self.localNameKey)
        error = nil
        Keychain.delete("microsoft")
        Keychain.delete("session")
        tokens = nil
        session = nil
        state = .signedOut
    }

    private func finish(_ ms: MicrosoftAuth.MicrosoftTokens) async throws {
        let s = try await MicrosoftAuth.minecraft(ms.accessToken)
        try Task.checkCancellation()
        defaults.removeObject(forKey: Self.localNameKey)
        tokens = ms
        session = s
        if let data = try? JSONEncoder().encode(ms) { Keychain.save(data, for: "microsoft") }
        if let data = try? JSONEncoder().encode(s) { Keychain.save(data, for: "session") }
        state = .signedIn(name: s.name)
    }

    /// Local profiles never create a session file or request Microsoft tokens.
    func launchArguments() async throws -> [String] {
        if case .local(let name) = state {
            return LocalAccount.launchArguments(name: name)
        }
        let session = try await sessionForPlay()
        let file = try Self.writeSessionFile(session)
        return ["--session-file", file.path]
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
