import SwiftUI

struct RootView: View {
    @Bindable var store: VaultStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                switch store.mode {
                case .loading:
                    ProgressView("Opening PasswordManager…")
                case .needsSetup:
                    CreateVaultView(store: store)
                case .unavailable:
                    VaultUnavailableView(store: store)
                case .locked:
                    UnlockVaultView(store: store)
                case .unlocked:
                    VaultView(store: store)
                }
            }

            if scenePhase != .active, store.mode == .unlocked {
                PrivacyCoverView()
            }
        }
        .task {
            await store.bootstrap()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                store.lock()
            }
        }
    }
}

private struct VaultUnavailableView: View {
    @Bindable var store: VaultStore

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 58))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Vault Needs Recovery")
                .font(.largeTitle.bold())
            Text("PasswordManager found encrypted vault data but could not read a valid envelope. It will not create or overwrite a vault while those files remain unresolved.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let error = store.errorMessage {
                ErrorMessageView(message: error)
            }
            Button("Try Again", systemImage: "arrow.clockwise") {
                Task { await store.retryBootstrap() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: 520)
        .padding(32)
    }
}

private struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                Text("Vault Locked")
                    .font(.title2.bold())
            }
        }
        .ignoresSafeArea()
        .accessibilityLabel("Vault locked")
    }
}
