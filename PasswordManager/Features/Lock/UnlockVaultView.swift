import SwiftUI

struct UnlockVaultView: View {
    @Bindable var store: VaultStore
    @State private var masterPassword = ""
    @FocusState private var isPasswordFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Vault Locked")
                    .font(.largeTitle.bold())
                Text("Unlock to access your credentials")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                if store.biometricQuickUnlockEnabled && store.biometricAvailability.isAvailable {
                    Button {
                        Task { await store.unlockWithBiometrics() }
                    } label: {
                        Label(
                            "Unlock with \(store.biometricAvailability.name)",
                            systemImage: store.biometricAvailability.systemImage
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.isBusy)

                    Text("or use your master password")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SecureField("Master password", text: $masterPassword)
                    .textFieldStyle(.roundedBorder)
                    .focused($isPasswordFocused)
                    .onSubmit(unlock)
                    .accessibilityIdentifier("unlock-master-password")

                Button(action: unlock) {
                    if store.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Unlock")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(masterPassword.isEmpty || store.isBusy)
                .accessibilityIdentifier("unlock-vault-button")

                if let error = store.errorMessage {
                    ErrorMessageView(message: error)
                }
            }
            .frame(maxWidth: 400)
            Spacer()
        }
        .padding(32)
        .onAppear {
            if store.biometricQuickUnlockEnabled && store.biometricAvailability.isAvailable {
                Task { await store.unlockWithBiometrics() }
            } else {
                isPasswordFocused = true
            }
        }
        .privacySensitive()
    }

    private func unlock() {
        guard !masterPassword.isEmpty else { return }
        Task {
            if await store.unlock(masterPassword: masterPassword) {
                masterPassword = ""
            }
        }
    }
}
