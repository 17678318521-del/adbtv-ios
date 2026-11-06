import SwiftUI
import UIKit

@main
struct ADBTVApp: App {
    @StateObject private var adb = ADBService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(adb)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var adb: ADBService
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            ConnectView()
                .tabItem { Label("连接", systemImage: "bolt.horizontal.circle") }
                .tag(0)

            AppsView()
                .tabItem { Label("应用", systemImage: "square.grid.2x2") }
                .tag(1)

            RemoteView()
                .tabItem { Label("投屏遥控", systemImage: "tv") }
                .tag(2)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(3)
        }
        .tint(Theme.primaryDeep)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .white
            appearance.shadowColor = UIColor(Theme.divider)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        .onChange(of: adb.state) { _ in
            if case .connected = adb.state, tab == 0 {
                // 连接成功后自动跳到投屏页
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation { tab = 2 }
                }
            }
        }
    }
}
