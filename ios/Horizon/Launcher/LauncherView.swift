import SwiftUI
import UniformTypeIdentifiers

/// The launcher: account, resources, worlds and Play, in Liquid Glass.
struct LauncherView: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var account: AccountStore
    @EnvironmentObject var controls: ControlLayout

    @State private var showSignIn = false
    @State private var localName = ""
    @State private var showSettings = false
    @State private var showControls = false
    @State private var picking = false
    @State private var world: String?

    var body: some View {
        ZStack {
            LauncherBackdrop()
            GeometryReader { geo in
                let wide = geo.size.width > geo.size.height
                ScrollView {
                    Group {
                        if wide {
                            HStack(alignment: .top, spacing: 20) {
                                VStack(alignment: .leading, spacing: 20) { header; playCard }
                                    .frame(maxWidth: .infinity)
                                VStack(spacing: 16) { accountCard; resourcesCard; worldsCard }
                                    .frame(maxWidth: 420)
                            }
                        } else {
                            VStack(spacing: 16) { header; accountCard; resourcesCard; worldsCard; playCard }
                        }
                    }
                    .padding(24)
                    .frame(minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSignIn) { SignInView().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(model.settings).presentationDetents([.medium, .large])
        }
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
        .onAppear { model.refreshWorlds(); world = model.settings.lastWorld.isEmpty ? nil : model.settings.lastWorld }
    }

    // MARK: Cards

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Horizon")
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
            Text("Java Edition 26.3 на Rust · iOS")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountCard: some View {
        Card(title: "Аккаунт", symbol: "person.crop.circle.fill") {
            switch account.state {
            case .signedIn(let name), .local(let name):
                HStack {
                    Text(name).font(.title3.bold())
                    Spacer()
                    Button("Выйти", role: .destructive) { account.signOut() }.glassButton()
                }
                if case .local = account.state {
                    Text("Локальный аккаунт").font(.footnote).foregroundStyle(.secondary)
                    Text("Одиночная игра и серверы без проверки Microsoft-аккаунта.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Microsoft · Java Edition куплена").font(.footnote).foregroundStyle(.secondary)
                }
            case .working:
                ProgressView().frame(maxWidth: .infinity)
            default:
                TextField("Ник игрока", text: $localName)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { account.signInLocally(name: localName) }
                    .padding(12)
                    .glassCard(cornerRadius: 12)
                Text("3–16 символов: A–Z, a–z, 0–9 и _.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { account.signInLocally(name: localName) } label: {
                    Label("Войти локально", systemImage: "person.fill").frame(maxWidth: .infinity)
                }
                .glassButton(prominent: true)
                Divider()
                Text("Или войди через Microsoft-аккаунт, на котором куплен Minecraft: Java Edition.")
                    .font(.callout).foregroundStyle(.secondary)
                Button { showSignIn = true; account.startSignIn() } label: {
                    Label("Войти через Microsoft", systemImage: "key.fill").frame(maxWidth: .infinity)
                }
                .glassButton()
                .disabled(!account.configured)
                if !account.configured {
                    Text("Вход Microsoft недоступен в этой сборке. Можно войти локально.").font(.footnote).foregroundStyle(.orange)
                }
            }
            if let e = account.error {
                Text(e).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var resourcesCard: some View {
        Card(title: "Ресурсы игры", symbol: "shippingbox.fill") {
            HStack {
                Image(systemName: model.resourcesReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.resourcesReady ? .green : .yellow)
                Text(model.resourcesReady ? "Готовы (26.3)" : "Не найдены")
                Spacer()
                if model.importing { ProgressView() }
            }
            Text("Папка .local/horizon-client/26.3 из horizon-prepare. Выбери её в «Файлах» или скопируй в Documents/resources/26.3 через Finder.")
                .font(.footnote).foregroundStyle(.secondary)
            Button { picking = true } label: {
                Label("Импортировать папку", systemImage: "folder.badge.plus").frame(maxWidth: .infinity)
            }
            .glassButton()
            .disabled(model.importing)
        }
    }

    private var worldsCard: some View {
        Card(title: "Миры", symbol: "globe.europe.africa.fill") {
            if model.worlds.isEmpty {
                Text("Пока нет миров: создай мир в меню игры.").font(.callout).foregroundStyle(.secondary)
            } else {
                Picker("Мир", selection: $world) {
                    Text("Главное меню").tag(String?.none)
                    ForEach(model.worlds, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var playCard: some View {
        VStack(spacing: 14) {
            GlassGroup(spacing: 12) {
                HStack(spacing: 12) {
                    Button { model.play(world: world) } label: {
                        Label(world.map { "Играть: \($0)" } ?? "Играть", systemImage: "play.fill")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .glassButton(prominent: true)
                    .disabled(!model.canPlay)

                    Button { showControls = true } label: {
                        Image(systemName: "gamecontroller.fill").font(.title2).padding(10)
                    }
                    .glassButton()
                    .accessibilityLabel("Управление")

                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill").font(.title2).padding(10)
                    }
                    .glassButton()
                    .accessibilityLabel("Настройки")
                }
            }
            if let status = model.status {
                Text(status).font(.callout).foregroundStyle(.white)
                    .padding(12).glassCard(cornerRadius: 16)
            } else if !model.canPlay {
                Text(hint).font(.footnote).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.top, 8)
    }

    private var hint: LocalizedStringKey {
        if account.hasAccount {
            return "Импортируй ресурсы, чтобы играть."
        }
        return "Войди в аккаунт, чтобы играть."
    }
}

/// A launcher section on glass.
struct Card<Content: View>: View {
    var title: LocalizedStringKey
    var symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// The device code to enter at microsoft.com/link.
struct SignInView: View {
    @EnvironmentObject var account: AccountStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                switch account.state {
                case .code(let code, let url):
                    Text("Открой страницу входа Microsoft и введи код:")
                        .multilineTextAlignment(.center)
                    Text(code)
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .glassCard(cornerRadius: 20)
                        .textSelection(.enabled)
                    Text("Код уже скопирован.").font(.footnote).foregroundStyle(.secondary)
                    Button { openURL(url) } label: {
                        Label("Открыть \(url.host ?? "microsoft.com")", systemImage: "safari")
                    }
                    .glassButton(prominent: true)
                    ProgressView("Ждём подтверждения…")
                case .signedIn(let name), .local(let name):
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
                    Text("Вход выполнен: \(name)").font(.title3.bold())
                    Button("Готово") { dismiss() }.glassButton(prominent: true)
                case .working:
                    ProgressView("Проверяем аккаунт…")
                case .signedOut:
                    if let e = account.error {
                        Text(e).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                    Button("Попробовать снова") { account.startSignIn() }.glassButton(prominent: true)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Вход через Microsoft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { account.cancelSignIn(); dismiss() }
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: LauncherSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Графика") {
                    LabeledContent("Дальность прорисовки: \(Int(settings.renderDistance)) чанков") {
                        Slider(value: $settings.renderDistance, in: 2...16, step: 1)
                    }
                }
                Section("Управление") {
                    LabeledContent("Чувствительность обзора") {
                        Slider(value: $settings.sensitivity, in: 0.05...1)
                    }
                    LabeledContent("Размер кнопок") {
                        Slider(value: $settings.controlScale, in: 0.6...1.6)
                    }
                    LabeledContent("Прозрачность кнопок") {
                        Slider(value: $settings.controlOpacity, in: 0.2...1)
                    }
                }
                Section {
                    Text("Тап по экрану: использовать/поставить. Удержание: ломать/бить. Свайп: обзор. В меню и инвентаре палец работает как мышь.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { settings.save(); dismiss() }
                }
            }
        }
    }
}
