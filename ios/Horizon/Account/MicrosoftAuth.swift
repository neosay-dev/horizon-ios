import Foundation

/// Microsoft sign-in for Minecraft: Java Edition, as docs/microsoft-account.md describes it:
/// the device-code flow, then Xbox Live, XSTS, the Minecraft services, entitlements and profile.
///
/// The client ID is this app's own Azure registration (Info.plist `HZMSAClientID`), approved
/// for the Minecraft services by Mojang. Never Horizon's or another launcher's
/// (docs/forking.md, "Microsoft sign-in in a fork").
enum MicrosoftAuth {
    struct DeviceCode: Decodable {
        let device_code: String
        let user_code: String
        let verification_uri: String
        let expires_in: Int
        let interval: Int
    }

    struct MicrosoftTokens: Codable {
        var accessToken: String
        var refreshToken: String
    }

    /// What the game needs (`--session-file`, horizon-client-render/src/auth.rs).
    struct Session: Codable {
        var name: String
        var uuid: String
        var accessToken: String
        var xuid: String?
        var expires: Date
    }

    enum AuthError: LocalizedError {
        case notConfigured
        case declined
        case expired
        case noXbox
        case child
        case notApproved
        case doesNotOwn
        case noProfile
        case http(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return String(localized: "В этой сборке нет Microsoft Client ID. Добавь свой HZMSAClientID в ios/project.yml (README).")
            case .declined: return String(localized: "Вход отменён.")
            case .expired: return String(localized: "Код истёк. Попробуй ещё раз.")
            case .noXbox: return String(localized: "У аккаунта нет профиля Xbox. Создай его на xbox.com.")
            case .child: return String(localized: "Детский аккаунт: нужно разрешение в семейной группе Microsoft.")
            case .notApproved: return String(localized: "Это приложение ещё не одобрено Mojang для входа (App ID review).")
            case .doesNotOwn: return String(localized: "На этом аккаунте не куплен Minecraft: Java Edition.")
            case .noProfile: return String(localized: "Создай профиль Minecraft на minecraft.net.")
            case .http(let s): return s
            }
        }
    }

    static var clientID: String? {
        let id = Bundle.main.object(forInfoDictionaryKey: "HZMSAClientID") as? String
        return (id?.isEmpty ?? true) ? nil : id
    }

    private static let scope = "XboxLive.signin offline_access"
    private static let tokenURL = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!

    // MARK: Microsoft

    static func deviceCode() async throws -> DeviceCode {
        guard let clientID else { throw AuthError.notConfigured }
        let url = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode")!
        return try await form(url, ["client_id": clientID, "scope": scope])
    }

    static func poll(_ code: DeviceCode) async throws -> MicrosoftTokens {
        guard let clientID else { throw AuthError.notConfigured }
        var interval = UInt64(max(code.interval, 1))
        let deadline = Date().addingTimeInterval(TimeInterval(code.expires_in))
        while Date() < deadline {
            try await Task.sleep(nanoseconds: interval * 1_000_000_000)
            let (data, _) = try await post(tokenURL, form: [
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "client_id": clientID,
                "device_code": code.device_code,
            ])
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String {
                return MicrosoftTokens(accessToken: access, refreshToken: refresh)
            }
            switch json["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "authorization_declined": throw AuthError.declined
            case "expired_token", "bad_verification_code": throw AuthError.expired
            default: throw AuthError.http(json["error_description"] as? String ?? "Microsoft sign-in failed")
            }
        }
        throw AuthError.expired
    }

    static func refresh(_ tokens: MicrosoftTokens) async throws -> MicrosoftTokens {
        guard let clientID else { throw AuthError.notConfigured }
        let (data, _) = try await post(tokenURL, form: [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": tokens.refreshToken,
            "scope": scope,
        ])
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let access = json["access_token"] as? String else {
            throw AuthError.http(json["error_description"] as? String ?? "Microsoft refresh failed")
        }
        return MicrosoftTokens(accessToken: access, refreshToken: json["refresh_token"] as? String ?? tokens.refreshToken)
    }

    // MARK: Xbox Live → Minecraft

    /// From a Microsoft access token to a Minecraft session, checking the account owns the game.
    static func minecraft(_ msAccessToken: String) async throws -> Session {
        let xbl: [String: Any] = try await json(
            URL(string: "https://user.auth.xboxlive.com/user/authenticate")!,
            body: ["Properties": ["AuthMethod": "RPS", "SiteName": "user.auth.xboxlive.com",
                                  "RpsTicket": "d=\(msAccessToken)"],
                   "RelyingParty": "http://auth.xboxlive.com", "TokenType": "JWT"])
        guard let xblToken = xbl["Token"] as? String else { throw AuthError.http("Xbox Live sign-in failed") }

        let (xstsData, xstsResponse) = try await post(
            URL(string: "https://xsts.auth.xboxlive.com/xsts/authorize")!,
            json: ["Properties": ["SandboxId": "RETAIL", "UserTokens": [xblToken]],
                   "RelyingParty": "rp://api.minecraftservices.com/", "TokenType": "JWT"])
        let xsts = (try? JSONSerialization.jsonObject(with: xstsData)) as? [String: Any] ?? [:]
        if xstsResponse.statusCode == 401 {
            switch xsts["XErr"] as? Int {
            case 2148916233: throw AuthError.noXbox
            case 2148916238: throw AuthError.child
            default: throw AuthError.http("XSTS: \(xsts["XErr"] ?? xstsResponse.statusCode)")
            }
        }
        guard let xstsToken = xsts["Token"] as? String,
              let claims = (xsts["DisplayClaims"] as? [String: Any])?["xui"] as? [[String: Any]],
              let uhs = claims.first?["uhs"] as? String
        else { throw AuthError.http("XSTS sign-in failed") }
        let xuid = claims.first?["xid"] as? String

        let (loginData, loginResponse) = try await post(
            URL(string: "https://api.minecraftservices.com/authentication/login_with_xbox")!,
            json: ["identityToken": "XBL3.0 x=\(uhs);\(xstsToken)"])
        if loginResponse.statusCode == 403 { throw AuthError.notApproved }
        let login = (try? JSONSerialization.jsonObject(with: loginData)) as? [String: Any] ?? [:]
        guard let mcToken = login["access_token"] as? String else { throw AuthError.http("Minecraft sign-in failed") }
        let expiresIn = login["expires_in"] as? Double ?? 86_400

        // The owner gate: the game only starts for an account that owns Java Edition.
        let entitlements: [String: Any] = try await get(
            URL(string: "https://api.minecraftservices.com/entitlements/mcstore")!, bearer: mcToken)
        let items = entitlements["items"] as? [[String: Any]] ?? []
        let names = Set(items.compactMap { $0["name"] as? String })
        guard names.contains("game_minecraft") || names.contains("product_minecraft") else {
            throw AuthError.doesNotOwn
        }

        let (profileData, profileResponse) = try await request(
            URL(string: "https://api.minecraftservices.com/minecraft/profile")!, bearer: mcToken)
        if profileResponse.statusCode == 404 { throw AuthError.noProfile }
        let profile = (try? JSONSerialization.jsonObject(with: profileData)) as? [String: Any] ?? [:]
        guard let id = profile["id"] as? String, let name = profile["name"] as? String else {
            throw AuthError.noProfile
        }
        return Session(name: name, uuid: id, accessToken: mcToken, xuid: xuid,
                       expires: Date().addingTimeInterval(expiresIn - 300))
    }

    // MARK: HTTP

    private static func form<T: Decodable>(_ url: URL, _ fields: [String: String]) async throws -> T {
        let (data, response) = try await post(url, form: fields)
        guard response.statusCode == 200 else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AuthError.http(json?["error_description"] as? String ?? "HTTP \(response.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func post(_ url: URL, form fields: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = fields.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&").data(using: .utf8)
        return try await send(req)
    }

    private static func post(_ url: URL, json body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req)
    }

    private static func json(_ url: URL, body: [String: Any]) async throws -> [String: Any] {
        let (data, response) = try await post(url, json: body)
        guard (200..<300).contains(response.statusCode) else { throw AuthError.http("HTTP \(response.statusCode) \(url.host ?? "")") }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func request(_ url: URL, bearer: String) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    private static func get(_ url: URL, bearer: String) async throws -> [String: Any] {
        let (data, response) = try await request(url, bearer: bearer)
        guard response.statusCode == 200 else { throw AuthError.http("HTTP \(response.statusCode) \(url.path)") }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AuthError.http("No HTTP response") }
        return (data, http)
    }
}
