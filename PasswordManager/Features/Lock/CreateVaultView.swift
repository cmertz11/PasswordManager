import SwiftUI

struct CreateVaultView: View {
    @Bindable var store: VaultStore
    @State private var masterPassword = ""
    @State private var confirmation = ""
    @State private var enableBiometrics = false
    @FocusState private var focusedField: Field?

    private enum Field { case password, confirmation }

    private var canCreate: Bool {
        masterPassword.count >= 12 && masterPassword == confirmation && !store.isBusy
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Create Your Vault")
                        .font(.largeTitle.bold())
                    Text("Your master password encrypts the vault and cannot be recovered.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    SecureField("Master password", text: $masterPassword)
                        .focused($focusedField, equals: .password)
                        .accessibilityIdentifier("create-master-password")
                        .onSubmit { focusedField = .confirmation }
                    SecureField("Confirm master password", text: $confirmation)
                        .focused($focusedField, equals: .confirmation)
                        .accessibilityIdentifier("create-master-password-confirmation")
                        .onSubmit(create)

                    Label("At least 12 characters; spaces are welcome", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if store.biometricAvailability.isAvailable {
                        Toggle(isOn: $enableBiometrics) {
                            Label(
                                "Enable \(store.biometricAvailability.name)",
                                systemImage: store.biometricAvailability.systemImage
                            )
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)

                if let error = store.errorMessage {
                    ErrorMessageView(message: error)
                }

                Button(action: create) {
                    if store.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Create Encrypted Vault")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canCreate)
                .accessibilityIdentifier("create-vault-button")
            }
            .frame(maxWidth: 460)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            enableBiometrics = store.biometricAvailability.isAvailable
            focusedField = .password
        }
        .privacySensitive()
    }

    private func create() {
        guard canCreate else { return }
        Task {
            if await store.createVault(masterPassword: masterPassword, enableBiometrics: enableBiometrics) {
                masterPassword = ""
                confirmation = ""
            }
        }
    }
}

struct ErrorMessageView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}
