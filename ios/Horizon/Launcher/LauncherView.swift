import SwiftUI
import UniformTypeIdentifiers

/// The launcher, as the original Horizon launcher looks (launcher/: the mark and Horizon at the
/// top left, the pages as pills at the top right, numbered rows), sized for an iPhone in
/// landscape. The pages are the original's that work on iOS: Play, Mods, What's new, Settings.
struct LauncherView: View {
    enum Page: String, CaseIterable {
        case play, mods, news, settings
        var title: String {
            switch self {
            case .play: return "Играть"
            case .mods: return "Моды"
            case .news: return "Новое"
            case .settings: return "Настройки"
            }
        }
    }

    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var account: AccountStore
    @EnvironmentObject var controls: ControlLayout
    @StateObject private var mods = ModsStore()
    @StateObject private var news = NewsStore()

    @State private var page: Page = .play
    @State private var showAccount = false
    @State private var showSignIn = false
    @State private var showControls = false
    @State private var picking = false

    var body: some View {
        ZStack {
            HZ.page.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Group {
                    switch page {
                    case .play: PlayPage(mods: mods, page: $page, showAccount: $showAccount,
                                         showControls: $showControls, picking: $picking)
                    case .mods: ModsPage(mods: mods)
                    case .news: NewsPage(news: news)
                    case .settings: SettingsPage(showAccount: $showAccount, showControls: $showControls,
                                                 picking: $picking)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .tint(HZ.accent)
        .environmentObject(model.settings)
        .sheet(isPresented: $showAccount) {
            AccountSheet(showSignIn: $showSignIn)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showSignIn) { SignInView().presentationDetents([.large]) }
        .fullScreenCover(isPresented: $showControls) {
            ZStack {
                LauncherBackdrop()
                ControlEditorView(onDone: { showControls = false })
                    .environmentObject(controls).environmentObject(model.settings)
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.importResources(from: url) }
        }
        .onAppear { model.refreshWorlds(); mods.loadInstalled() }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            HorizonMark(size: 16)
            Text("Horizon").font(HZ.sans(14, .medium)).foregroundStyle(HZ.ink)
            Spacer(minLength: 12)
            HStack(spacing: 2) {
                ForEach(Page.allCases, id: \.self) { p in
                    Button { page = p } label: {
                        Text(p.title)
                            .font(HZ.sans(13, .medium))
                            .foregroundStyle(page == p ? HZ.ink : HZ.muted)
                            .padding(.horizontal, 12).frame(minHeight: 30)
                            .background(page == p ? HZ.pill : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

/// The page's scroll and margins: the original's 64 px gutter, narrower for a phone.
struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 24)
                .frame(maxWidth: 880, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}

/// The original's footer: the launcher's version in mono capitals, and its link.
struct Footer: View {
    var body: some View {
        HStack {
            Text("LAUNCHER \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
            Spacer()
            Link("GITHUB", destination: URL(string: "https://github.com/neosay-dev/horizon-ios")!)
                .foregroundStyle(HZ.muted)
        }
        .font(HZ.mono(11))
        .kerning(0.6)
        .foregroundStyle(HZ.faint)
        .padding(.top, 18)
    }
}

// MARK: - Play

struct PlayPage: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var account: AccountStore
    @EnvironmentObject var controls: ControlLayout
    @ObservedObject var mods: ModsStore
    @Binding var page: LauncherView.Page
    @Binding var showAccount: Bool
    @Binding var showControls: Bool
    @Binding var picking: Bool
    @State private var world: String?

    var body: some View {
        PageScroll {
            Eyebrow(text: "Minecraft 26.3",
                    status: model.resourcesReady ? "Готово" : "Нужны файлы",
                    statusColor: model.resourcesReady ? HZ.ready : HZ.warn)
            Text("Horizon")
                .font(HZ.sans(44, .medium)).foregroundStyle(HZ.ink)
                .padding(.top, 10)
            Text("Minecraft: Java Edition 26.3, переписанный на Rust. Порт для iPhone: тот же мир, те же правила, без Java.")
                .font(HZ.sans(14)).foregroundStyle(HZ.muted).lineSpacing(3)
                .frame(maxWidth: 520, alignment: .leading)
                .padding(.top, 8)

            HStack(spacing: 8) {
                worldMenu
                Spacer()
                Button { model.play(world: world) } label: {
                    Text("Играть").frame(minWidth: 96)
                }
                .buttonStyle(HZButton(kind: .accent))
                .disabled(!model.canPlay)
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            if let status = model.status {
                Text(status).font(HZ.sans(12)).foregroundStyle(HZ.danger).padding(.bottom, 10)
            } else if !model.canPlay {
                Text(account.hasAccount ? "Импортируй файлы игры, чтобы играть." : "Войди в аккаунт, чтобы играть.")
                    .font(HZ.sans(12)).foregroundStyle(HZ.muted).padding(.bottom, 10)
            }

            Hairline()
            NumberedRow(number: 1, title: "Файлы игры",
                        detail: model.resourcesReady ? "Готовы для Minecraft 26.3" :
                            "Не найдены. Нужна папка .local/horizon-client/26.3 из horizon-prepare.",
                        detailColor: model.resourcesReady ? HZ.muted : HZ.warn) {
                if model.importing { ProgressView() } else {
                    Button(model.resourcesReady ? "Заменить…" : "Импорт…") { picking = true }
                        .buttonStyle(HZButton(kind: model.resourcesReady ? .text : .pill))
                }
            }
            NumberedRow(number: 2, title: "Играешь как", detail: playingAs) {
                Button("Аккаунт…") { showAccount = true }.buttonStyle(HZButton(kind: account.hasAccount ? .text : .pill))
            }
            NumberedRow(number: 3, title: "Управление", detail: "Кнопки, стик и виртуальная мышь для меню") {
                Button("Редактор…") { showControls = true }.buttonStyle(HZButton(kind: .text))
            }
            NumberedRow(number: 4, title: "Моды", detail: modsLine) {
                Button("Открыть") { page = .mods }.buttonStyle(HZButton(kind: .text))
            }

            Wordmark()
            Footer()
        }
        .onAppear { world = model.settings.lastWorld.isEmpty ? nil : model.settings.lastWorld }
    }

    /// The original's version pill, here the world Play opens.
    private var worldMenu: some View {
        Menu {
            Button("Главное меню") { world = nil }
            if !model.worlds.isEmpty {
                Divider()
                ForEach(model.worlds, id: \.self) { name in
                    Button(name) { world = name }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(world ?? "Главное меню").font(HZ.mono(13)).foregroundStyle(HZ.ink).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(HZ.muted)
            }
            .padding(.horizontal, 14).frame(minHeight: 40)
            .background(HZ.pill, in: Capsule())
        }
    }

    private var playingAs: String {
        switch account.state {
        case .local(let name): return "\(name) · локально: онлайн-серверам нужен Microsoft-аккаунт"
        case .signedIn(let name): return "\(name) · Microsoft"
        default: return "Не выполнен вход"
        }
    }

    private var modsLine: String {
        let parts = ModKind.allCases.compactMap { kind -> String? in
            let n = mods.count(kind)
            return n > 0 ? "\(kind.title): \(n)" : nil
        }
        return parts.isEmpty ? "Ничего не установлено" : parts.joined(separator: " · ")
    }
}

/// The giant faded `horizon` under the original's Play page.
struct Wordmark: View {
    var body: some View {
        Text("horizon")
            .font(HZ.sans(132, .medium))
            .foregroundStyle(Color.white.opacity(0.035))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(height: 110, alignment: .top)
            .clipped()
            .padding(.top, 28)
            .accessibilityHidden(true)
    }
}

// MARK: - Mods

struct ModsPage: View {
    enum Tab: Hashable { case installed, horizon, modrinth }

    @ObservedObject var mods: ModsStore
    @State private var tab: Tab = .horizon
    @State private var kind: ModKind = .mod
    @State private var query = ""

    var body: some View {
        PageScroll {
            PageHead(title: "Моды",
                     subtitle: "Моды, ресурспаки и шейдеры из реестра Horizon и с Modrinth. Только то, что работает на iPhone: моды без кода.")
            HStack(spacing: 10) {
                Segmented(options: [(Tab.horizon, "Horizon"), (Tab.modrinth, "Modrinth"), (Tab.installed, "Установлено")],
                          selection: $tab)
                Spacer()
            }
            .padding(.top, 18)

            if tab != .installed {
                HStack(spacing: 10) {
                    Segmented(options: kinds.map { ($0, $0.title) }, selection: $kind)
                    searchField
                }
                .padding(.top, 10)
            }

            if let message = mods.message {
                Text(message).font(HZ.sans(12)).foregroundStyle(HZ.accentText).padding(.top, 12)
            }

            Group {
                switch tab {
                case .installed: installedList
                case .horizon: horizonList
                case .modrinth: modrinthList
                }
            }
            .padding(.top, 14)
            Footer()
        }
        .task { await mods.loadRegistry() }
        .onChange(of: tab) { _, new in
            if new == .modrinth && kind == .mod { kind = .resourcepack }
            refresh()
        }
        .onChange(of: kind) { _, _ in refresh() }
        .onChange(of: query) { _, _ in if tab == .modrinth { refresh() } }
    }

    /// Modrinth's mods are Java's (Fabric, Forge): they don't run here.
    private var kinds: [ModKind] { tab == .modrinth ? [.resourcepack, .shader] : ModKind.allCases }

    private func refresh() {
        if tab == .modrinth { mods.search(query, kind: kind) }
        if tab == .installed { mods.loadInstalled() }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(HZ.faint)
            TextField("", text: $query, prompt: Text("Поиск").foregroundStyle(HZ.faint))
                .font(HZ.sans(13)).foregroundStyle(HZ.ink)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search)
        }
        .padding(.horizontal, 12).frame(minHeight: 34)
        .background(HZ.pill, in: Capsule())
        .frame(maxWidth: 260)
    }

    private var horizonList: some View {
        let items = mods.registry.filter { $0.kind == kind && matches($0) }
        return VStack(alignment: .leading, spacing: 0) {
            if mods.loadingRegistry && mods.registry.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if let error = mods.registryError, mods.registry.isEmpty {
                Note(text: error, color: HZ.danger)
                Button("Повторить") { Task { await mods.loadRegistry() } }.buttonStyle(HZButton(kind: .pill)).padding(.top, 8)
            } else if items.isEmpty {
                Note(text: "В реестре Horizon пока нет \(kind == .mod ? "модов" : kind == .shader ? "шейдеров" : "ресурспаков") для этой игры.")
            } else {
                Hairline()
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in itemRow(i + 1, item) }
            }
        }
    }

    private var modrinthList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mods.searching && mods.modrinthHits.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if let error = mods.modrinthError {
                Note(text: error, color: HZ.danger)
            } else if mods.modrinthHits.isEmpty {
                Note(text: "Ничего не нашлось.")
            } else {
                Hairline()
                ForEach(Array(mods.modrinthHits.enumerated()), id: \.element.id) { i, item in itemRow(i + 1, item) }
            }
        }
        .onAppear { if mods.modrinthHits.isEmpty { refresh() } }
    }

    private var installedList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mods.installed.isEmpty {
                Note(text: "Пока ничего не установлено. Файлы лежат в «Файлах»: Horizon → game → horizon-mods, resourcepacks, shaderpacks.")
            } else {
                Hairline()
                ForEach(Array(mods.installed.enumerated()), id: \.element.id) { i, mod in
                    NumberedRow(number: i + 1, title: mod.name, detail: "\(mod.kind.title) · \(mod.file)") {
                        Button("Удалить") { mods.remove(mod) }.buttonStyle(HZButton(kind: .text))
                    }
                }
            }
        }
    }

    private func matches(_ item: ModItem) -> Bool {
        query.isEmpty || item.name.localizedCaseInsensitiveContains(query)
            || item.summary.localizedCaseInsensitiveContains(query)
    }

    private func itemRow(_ n: Int, _ item: ModItem) -> some View {
        HStack(spacing: 0) {
            Text(String(format: "%02d", n)).font(HZ.mono(11)).foregroundStyle(HZ.faint)
                .frame(width: 44, alignment: .leading)
            ModIcon(url: item.icon).padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(HZ.sans(14, .medium)).foregroundStyle(HZ.ink).lineLimit(1)
                Text(item.summary).font(HZ.sans(12)).foregroundStyle(HZ.muted).lineLimit(2)
                Text(byline(item)).font(HZ.mono(10)).foregroundStyle(HZ.faint).lineLimit(1)
            }
            Spacer(minLength: 16)
            if mods.busy.contains(item.id) {
                ProgressView()
            } else if mods.isInstalled(item) {
                Text("УСТАНОВЛЕНО").font(HZ.mono(11)).foregroundStyle(HZ.accentText)
            } else {
                Button("Установить") { mods.install(item) }.buttonStyle(HZButton(kind: .pill))
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(HZ.rule).frame(height: 1) }
    }

    private func byline(_ item: ModItem) -> String {
        var parts: [String] = []
        if !item.author.isEmpty { parts.append(item.author) }
        if item.downloads > 0 { parts.append("\(item.downloads.formatted(.number.notation(.compactName))) загрузок") }
        return parts.joined(separator: " · ")
    }
}

/// A project's icon, or a plain tile while it loads.
struct ModIcon: View {
    var url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().interpolation(.none).scaledToFill()
        } placeholder: {
            HZ.pill
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A line of text in place of a list.
struct Note: View {
    var text: String
    var color: Color = HZ.muted

    var body: some View {
        Text(text).font(HZ.sans(13)).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
    }
}

// MARK: - What's new

struct NewsPage: View {
    @ObservedObject var news: NewsStore

    var body: some View {
        PageScroll {
            PageHead(title: "Новое", subtitle: "Что изменилось в каждом релизе порта.")
                .padding(.bottom, 18)
            if news.loading && news.releases.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if let error = news.error, news.releases.isEmpty {
                Note(text: error, color: HZ.danger)
                Button("Повторить") { Task { await news.load() } }.buttonStyle(HZButton(kind: .pill))
            } else {
                Hairline()
                ForEach(news.releases) { release in
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: release.tag,
                                status: release.date?.formatted(date: .long, time: .omitted),
                                statusColor: HZ.muted)
                        Text(release.name).font(HZ.sans(22, .medium)).foregroundStyle(HZ.ink)
                        Text(markdown(release.body)).font(HZ.sans(13)).foregroundStyle(HZ.muted)
                            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                            .tint(HZ.accentText)
                    }
                    .padding(.vertical, 16)
                    .overlay(alignment: .bottom) { Rectangle().fill(HZ.rule).frame(height: 1) }
                }
                Link("Все релизы на GitHub", destination: NewsStore.page)
                    .font(HZ.sans(13, .medium)).foregroundStyle(HZ.accentText).padding(.top, 14)
            }
            Footer()
        }
        .task { if news.releases.isEmpty { await news.load() } }
    }

    /// Release notes are Markdown: headings become plain bold lines, the rest keeps its links.
    private func markdown(_ text: String) -> AttributedString {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        let cleaned = lines.map { line -> String in
            var l = String(line)
            if l.hasPrefix("#") { l = "**" + l.drop(while: { $0 == "#" || $0 == " " }) + "**" }
            if l.hasPrefix("- ") { l = "•  " + l.dropFirst(2) }
            if l == "---" { l = "" }
            return l
        }.joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: cleaned, options: options)) ?? AttributedString(text)
    }
}

// MARK: - Settings

struct SettingsPage: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var account: AccountStore
    @EnvironmentObject var settings: LauncherSettings
    @Binding var showAccount: Bool
    @Binding var showControls: Bool
    @Binding var picking: Bool

    var body: some View {
        PageScroll {
            PageHead(title: "Настройки", subtitle: "Аккаунт, графика, управление и файлы игры.")
                .padding(.bottom, 18)
            Hairline()
            NumberedRow(number: 1, title: "Аккаунт", detail: accountLine) {
                Button("Аккаунт…") { showAccount = true }.buttonStyle(HZButton(kind: .text))
            }
            sliderRow(2, "Дальность прорисовки", "\(Int(settings.renderDistance)) чанков. Больше: дальше видно, больше памяти.",
                      value: $settings.renderDistance, range: 2...128, step: 1)
            sliderRow(3, "Чувствительность обзора", "Насколько быстро поворачивает свайп.",
                      value: $settings.sensitivity, range: 0.05...1)
            sliderRow(4, "Размер кнопок", "\(Int(settings.controlScale * 100)) %",
                      value: $settings.controlScale, range: 0.6...1.6)
            sliderRow(5, "Прозрачность кнопок", "\(Int(settings.controlOpacity * 100)) %",
                      value: $settings.controlOpacity, range: 0.2...1)
            NumberedRow(number: 6, title: "Раскладка управления", detail: "Двигай, меняй размер, добавляй свои кнопки.") {
                Button("Редактор…") { showControls = true }.buttonStyle(HZButton(kind: .text))
            }
            NumberedRow(number: 7, title: "Файлы игры",
                        detail: model.resourcesReady ? "Готовы для Minecraft 26.3" : "Не найдены",
                        detailColor: model.resourcesReady ? HZ.muted : HZ.warn) {
                Button(model.resourcesReady ? "Заменить…" : "Импорт…") { picking = true }.buttonStyle(HZButton(kind: .text))
            }
            NumberedRow(number: 8, title: "Папка игры",
                        detail: "Миры, моды и логи: «Файлы» → На iPhone → Horizon.")
            Footer()
        }
        .onDisappear { settings.save() }
        .onChange(of: settings.prefs.renderDistance) { _, _ in settings.save() }
    }

    private var accountLine: String {
        switch account.state {
        case .local(let name): return "\(name) · локальный"
        case .signedIn(let name): return "\(name) · Microsoft"
        default: return "Не выполнен вход"
        }
    }

    private func sliderRow(_ n: Int, _ title: String, _ detail: String, value: Binding<Double>,
                           range: ClosedRange<Double>, step: Double? = nil) -> some View {
        NumberedRow(number: n, title: title, detail: detail) {
            Group {
                if let step {
                    Slider(value: value, in: range, step: step, onEditingChanged: { editing in if !editing { settings.save() } })
                } else {
                    Slider(value: value, in: range, onEditingChanged: { editing in if !editing { settings.save() } })
                }
            }
            .frame(width: 200)
        }
    }
}

// MARK: - Account

/// The original's Accounts…: a local nickname, or Microsoft.
struct AccountSheet: View {
    @EnvironmentObject var account: AccountStore
    @Environment(\.dismiss) private var dismiss
    @Binding var showSignIn: Bool
    @State private var localName = ""

    var body: some View {
        ZStack {
            HZ.page.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        PageHead(title: "Аккаунт", subtitle: "С кем играешь: локальный ник или Microsoft-аккаунт с купленным Java Edition.")
                        Button("Готово") { dismiss() }.buttonStyle(HZButton(kind: .pill))
                    }
                    .padding(.bottom, 18)
                    Hairline()
                    switch account.state {
                    case .signedIn(let name), .local(let name):
                        NumberedRow(number: 1, title: name, detail: isLocal ? "Локальный: одиночная игра и серверы без проверки Microsoft" : "Microsoft · Java Edition куплена") {
                            Button("Выйти") { account.signOut() }.buttonStyle(HZButton(kind: .text))
                        }
                    case .working:
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                    default:
                        NumberedRow(number: 1, title: "Локально", detail: "3–16 символов: A–Z, a–z, 0–9 и _") {
                            HStack(spacing: 8) {
                                TextField("", text: $localName, prompt: Text("Ник").foregroundStyle(HZ.faint))
                                    .font(HZ.sans(13)).foregroundStyle(HZ.ink)
                                    .textContentType(.username)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .submitLabel(.go)
                                    .onSubmit { _ = account.signInLocally(name: localName) }
                                    .padding(.horizontal, 12).frame(width: 160, height: 34)
                                    .background(HZ.pill, in: Capsule())
                                Button("Войти") { _ = account.signInLocally(name: localName) }
                                    .buttonStyle(HZButton(kind: .accent))
                            }
                        }
                        NumberedRow(number: 2, title: "Microsoft",
                                    detail: account.configured ? "Для онлайн-серверов. Нужен купленный Java Edition."
                                        : "Недоступно в этой сборке: нет client ID.",
                                    detailColor: account.configured ? HZ.muted : HZ.warn) {
                            Button("Войти…") {
                                // One sheet at a time: this one closes, then the code's opens.
                                account.startSignIn()
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showSignIn = true }
                            }
                                .buttonStyle(HZButton(kind: .pill))
                                .disabled(!account.configured)
                        }
                    }
                    if let e = account.error {
                        Text(e).font(HZ.sans(12)).foregroundStyle(HZ.danger).padding(.top, 10)
                    }
                }
                .padding(24)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var isLocal: Bool {
        if case .local = account.state { return true }
        return false
    }
}

/// The device code to enter at microsoft.com/link.
struct SignInView: View {
    @EnvironmentObject var account: AccountStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            HZ.page.ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    Text("Вход через Microsoft").font(HZ.sans(20, .medium)).foregroundStyle(HZ.ink)
                    Spacer()
                    Button("Закрыть") { account.cancelSignIn(); dismiss() }.buttonStyle(HZButton(kind: .pill))
                }
                Spacer(minLength: 0)
                switch account.state {
                case .code(let code, let url):
                    Text("Открой страницу входа Microsoft и введи код:")
                        .font(HZ.sans(14)).foregroundStyle(HZ.muted)
                    Text(code)
                        .font(HZ.mono(34)).foregroundStyle(HZ.ink)
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .background(HZ.pill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .textSelection(.enabled)
                    Text("Код уже скопирован.").font(HZ.sans(12)).foregroundStyle(HZ.faint)
                    Button("Открыть \(url.host ?? "microsoft.com")") { openURL(url) }
                        .buttonStyle(HZButton(kind: .accent))
                    ProgressView("Ждём подтверждения…").font(HZ.sans(12))
                case .signedIn(let name), .local(let name):
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(HZ.ready)
                    Text("Вход выполнен: \(name)").font(HZ.sans(18, .medium)).foregroundStyle(HZ.ink)
                    Button("Готово") { dismiss() }.buttonStyle(HZButton(kind: .accent))
                case .working:
                    ProgressView("Проверяем аккаунт…").font(HZ.sans(12))
                case .signedOut:
                    if let e = account.error {
                        Text(e).font(HZ.sans(13)).foregroundStyle(HZ.danger).multilineTextAlignment(.center)
                    }
                    Button("Попробовать снова") { account.startSignIn() }.buttonStyle(HZButton(kind: .accent))
                }
                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
    }
}
