import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var launcher: Launcher? = nil
    @State private var page = 0

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 28, weight: .medium)).foregroundStyle(.blue)
                    .padding(.bottom, 4)
                Text("Window Menu").font(.system(size: 17, weight: .semibold))
                Text("いつもの操作を、近くに。")
                    .font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 25)
                navigation("配置と動作", symbol: "rectangle.3.group", index: 0)
                navigation("固定アプリ", symbol: "pin", index: 1)
                navigation("対象アプリ", symbol: "macwindow", index: 2)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(model.trusted && model.menusEnabled ? .green : .orange).frame(width: 6, height: 6)
                    Text(model.trusted ? "\(model.windowCount) ウィンドウを検出" : "アクセス許可が必要")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Text("v0.2.0 · macOS 13+").font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 3)
            }
            .padding(20).frame(width: 180).frame(maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let error = model.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12))
                            Button("閉じる") { model.error = nil }
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    switch page {
                    case 1: pinnedApps
                    case 2: exclusions
                    default: overview
                    }
                }.padding(28)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 800, height: 700)
    }

    private func navigation(_ title: String, symbol: String, index: Int) -> some View {
        Button { page = index } label: {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: page == index ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9).padding(.horizontal, 10)
                .background(page == index ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            header("Dockを、メニューバーへ。", subtitle: "アプリをひとつに並べて、すばやく切り替え。")
            if let launcher { TaskbarPreviewCard(launcher: launcher) }
            else { DesktopPreview().frame(height: 173) }
            if !model.trusted {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.orange).font(.system(size: 21))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ウィンドウメニューの利用を許可").font(.system(size: 13, weight: .semibold))
                        Text("システム設定の「アクセシビリティ」で Window Menu をオンにしてください。許可後は自動で表示が始まります。")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("システム設定を開く") { model.requestAccessibility() }.padding(.top, 2)
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(spacing: 0) {
                settingRow("全ウィンドウにメニューを表示", detail: "現在のデスクトップにある通常のウィンドウが対象です。", symbol: "macwindow",
                           value: Binding(get: { model.menusEnabled }, set: model.setMenus))
                Divider().padding(.leading, 45)
                settingRow("上部にタスクバーを表示", detail: "選択中は青い下線、起動中は小さな印で表示します。", symbol: "square.grid.2x2",
                           value: Binding(get: { model.launcherEnabled }, set: model.setLauncher))
                Divider().padding(.leading, 45)
                settingRow("下のDockを自動非表示にする", detail: "このアプリの終了時に、変更前の設定へ戻します。", symbol: "dock.rectangle",
                           value: Binding(get: { model.dockHidden }, set: model.setDockHidden))
            }.padding(.horizontal, 16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("ウィンドウメニューの位置").font(.system(size: 12))
                    Spacer()
                    Picker("位置", selection: Binding(get: { model.insidePlacement }, set: model.setInside)) {
                        Text("上端に追従").tag(false)
                        Text("タイトルバーの下").tag(true)
                    }.labelsHidden().frame(width: 170)
                }
                Text("上端に空きがない場合は、タイトルバーの下に重ねて表示します。アプリのツールバーと重なる場合は「対象アプリ」で除外できます。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("タスクバーのアプリ数").font(.system(size: 12))
                    Spacer()
                    Picker("タスクバーのアプリ数", selection: Binding(get: { model.iconLimit }, set: model.setIconLimit)) {
                        Text("自動（画面幅に合わせる）").tag(0)
                        ForEach(1...16, id: \.self) { count in Text("最大\(count)個").tag(count) }
                    }.labelsHidden().frame(width: 190)
                }
                Text("入りきらないアプリは「⌄」から。固定アプリはドラッグで並べ替えられます。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Divider()
            Text("元のメニューバーは残ります。Dockは画面端にポインタを置くと再表示されます。フルスクリーン・最小化中のウィンドウ、一部の独自メニューには対応していません。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Dockを元の設定に戻す") { model.restoreDock() }
                Spacer()
                Button("終了") { NSApp.terminate(nil) }
            }.font(.system(size: 11))
        }
    }

    private var pinnedApps: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("よく使うアプリを、上へ。", subtitle: "上から順に、タスクバーの左から右へ並びます。")
            HStack {
                Button("アプリを追加…") { model.addApplications() }
                Button("Dockから取り込む") { model.importDock() }
            }
            if model.pinnedPaths.isEmpty {
                Text("固定アプリはありません。起動中のアプリは自動で表示されます。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 20)
            }
            ForEach(model.pinnedPaths, id: \.self) { path in
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")).font(.system(size: 13))
                        if !FileManager.default.fileExists(atPath: path) { Text("アプリが見つかりません").font(.system(size: 10)).foregroundStyle(.orange) }
                    }
                    Spacer()
                    Button { model.movePin(path, offset: -1) } label: { Image(systemName: "chevron.up") }
                        .disabled(model.pinnedPaths.first == path).help("左へ移動")
                        .accessibilityLabel("\(FileManager.default.displayName(atPath: path))を左へ移動")
                    Button { model.movePin(path, offset: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(model.pinnedPaths.last == path).help("右へ移動")
                        .accessibilityLabel("\(FileManager.default.displayName(atPath: path))を右へ移動")
                    Button("解除") { model.togglePin(path) }.font(.system(size: 11))
                }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            }
            Text("メニューバーのアプリアイコンを右クリックして、固定や解除もできます。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var exclusions: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("アプリごとに調整。", subtitle: "表示が重なるアプリや、独自のメニューを持つアプリを除外できます。")
            ForEach(availableExclusions, id: \.id) { app in
                Toggle(isOn: Binding(get: { !model.excludedBundleIDs.contains(app.id) }, set: { _ in model.toggleExclusion(app.id) })) {
                    Text(app.name).font(.system(size: 13))
                }.toggleStyle(.switch).controlSize(.small).padding(13)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            }
            Text("オンのアプリにウィンドウメニューを表示します。起動中のアプリと、以前に除外したアプリが一覧に表示されます。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var availableExclusions: [(id: String, name: String)] {
        var names: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            if let id = app.bundleIdentifier { names[id] = app.localizedName ?? id }
        }
        for id in model.excludedBundleIDs where names[id] == nil { names[id] = id }
        return names.map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    private func header(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 24, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private func settingRow(_ title: String, detail: String, symbol: String, value: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(.blue).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }.padding(.vertical, 15)
    }
}

private struct TaskbarPreviewCard: View {
    @ObservedObject var launcher: Launcher
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("上部タスクバー", systemImage: "rectangle.topthird.inset.filled")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(launcher.layout.visibleCount) / \(launcher.apps.count) アプリ")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack {
                Spacer(minLength: 0)
                TaskbarPreview(launcher: launcher).frame(width: launcher.layout.width, height: 32)
                Spacer(minLength: 0)
            }.padding(.vertical, 10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            Text("このプレビューもクリックできます。左のアイコンで全アプリを検索、右クリックで固定や終了。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(16).background(Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DesktopPreview: View {
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(red: 0.78, green: 0.86, blue: 0.91), Color(red: 0.9, green: 0.91, blue: 0.84)], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: 9) {
                    Image(systemName: "apple.logo")
                    Text("Finder").bold()
                    Text("ファイル")
                    Spacer()
                    ForEach(["folder.fill", "safari.fill", "envelope.fill", "music.note"], id: \.self) { name in
                        Image(systemName: name).foregroundStyle(.blue).font(.system(size: 11))
                    }
                    Text("12:00").padding(.leading, 8)
                }.font(.system(size: 8)).padding(.horizontal, 13).frame(height: 23).background(.ultraThinMaterial)
                miniature("メモ", color: .yellow).frame(width: geo.size.width * 0.47, height: 96).offset(x: 30, y: 46)
                miniature("Safari", color: .blue).frame(width: geo.size.width * 0.49, height: 103).offset(x: geo.size.width * 0.46, y: 60)
            }.clipShape(RoundedRectangle(cornerRadius: 12))
        }.accessibilityLabel("上部にアプリのアイコン、各ウィンドウにメニューを表示する配置イメージ")
    }

    private func miniature(_ app: String, color: Color) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach([Color.red, .yellow, .green], id: \.self) { color in Circle().fill(color.opacity(0.7)).frame(width: 5, height: 5) }
                Spacer()
                Text(app).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
            }.padding(8).background(Color(nsColor: .windowBackgroundColor))
            HStack(spacing: 10) {
                Text(app).bold()
                Text("ファイル")
                Text("編集")
                Text("表示")
                Spacer(minLength: 0)
            }.font(.system(size: 8)).padding(.horizontal, 8).frame(height: 20).background(color.opacity(0.13))
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.14)).frame(width: 65, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.08)).frame(height: 4)
                Spacer(minLength: 0)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }
}
