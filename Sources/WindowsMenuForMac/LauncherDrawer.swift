import SwiftUI

struct LauncherDrawer: View {
    @ObservedObject var launcher: Launcher
    @ObservedObject var model: AppModel
    @State private var query = ""
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    private var filtered: [LauncherApp] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return launcher.apps.filter { search.isEmpty || $0.name.localizedStandardContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("アプリ").font(.system(size: 20, weight: .semibold))
                    Text("\(launcher.apps.filter { $0.running != nil }.count)個が起動中").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "square.grid.2x2.fill").font(.system(size: 20)).foregroundStyle(.blue)
            }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 15)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("アプリを検索", text: $query).textFieldStyle(.plain)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
            }.font(.system(size: 12)).padding(10)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("固定済み", apps: filtered.filter(\.pinned))
                    section("起動中", apps: filtered.filter { !$0.pinned })
                    if filtered.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").font(.system(size: 25)).foregroundStyle(.tertiary)
                            Text(query.isEmpty ? "アプリを固定して始めましょう" : "一致するアプリがありません")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 50)
                    }
                }.padding(20)
            }
            Divider()
            HStack {
                Button { launcher.settings() } label: { Label("設定", systemImage: "gearshape") }
                Spacer()
                Button { launcher.settings(); model.addApplications() } label: { Label("アプリを追加", systemImage: "plus") }
            }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary).padding(16)
        }.frame(width: 416, height: 470)
    }

    @ViewBuilder private func section(_ name: String, apps: [LauncherApp]) -> some View {
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(apps) { app in
                        AppTile(app: app) { launcher.open(app) }
                            .contextMenu {
                                Button("開く") { launcher.open(app) }
                                Button(app.pinned ? "固定を解除" : "タスクバーに固定") { model.togglePin(app.path) }
                                if app.pinned {
                                    Button("左へ移動") { model.movePin(app.path, offset: -1) }
                                    Button("右へ移動") { model.movePin(app.path, offset: 1) }
                                }
                                if let running = app.running { Divider(); Button("終了") { running.terminate() } }
                            }
                    }
                }
            }
        }
    }
}

private struct AppTile: View {
    let app: LauncherApp
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(nsImage: app.icon).resizable().frame(width: 34, height: 34)
                Capsule().fill(app.isActive ? Color.accentColor : Color.secondary.opacity(0.6))
                    .frame(width: app.isActive ? 14 : 5, height: 2).opacity(app.running != nil ? 1 : 0)
                Text(app.name).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 26, alignment: .top)
            }.frame(maxWidth: .infinity).padding(.top, 9).padding(.horizontal, 3).padding(.bottom, 3)
                .background((hovered || app.isActive) ? Color.accentColor.opacity(hovered ? 0.13 : 0.07) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).onHover { hovered = $0 }.help(app.name)
            .accessibilityLabel(app.name).accessibilityValue(app.isActive ? "選択中" : app.running != nil ? "起動中" : "固定済み")
    }
}
