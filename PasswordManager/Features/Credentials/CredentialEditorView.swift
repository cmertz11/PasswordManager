import SwiftUI

struct CredentialEditorView: View {
    private enum UsernameKeyboard {
        case email
        case ascii
    }

    @Bindable var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Credential
    @State private var isPresentingGenerator = false
    @State private var isSecretRevealed = false

    init(store: VaultStore, credential: Credential?) {
        self.store = store
        _draft = State(initialValue: credential ?? Credential(name: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Credential") {
                    Picker("Credential Type", selection: $draft.kind) {
                        ForEach(CredentialKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("credential-kind")

                    TextField("Name", text: $draft.name)
                        .textContentType(.name)
                        .accessibilityIdentifier("credential-name")
                    switch draft.kind {
                    case .website:
                        loginFields(usernameLabel: "Username or email", usernameKeyboard: .email)
                        TextField("Website", text: $draft.website)
                            .textContentType(.URL)
                            .accessibilityIdentifier("credential-website")
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif

                        TextField("Allowed Password Symbols (Optional)", text: $draft.allowedPasswordSymbols)
                            .font(.body.monospaced())
                            .accessibilityIdentifier("credential-allowed-password-symbols")
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            #endif

                        Text("Leave blank to use the generator default. This rule is saved with this website and supplied to the password generator.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .ssh:
                        TextField("Custom SSH Command (Optional)", text: $draft.sshCommand, axis: .vertical)
                            .font(.body.monospaced())
                            .lineLimit(2...6)
                            .accessibilityIdentifier("credential-ssh-command")
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            #endif

                        Text("When set, Open SSH runs this command as entered and ignores the username and host below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        loginFields(usernameLabel: "SSH Username", usernameKeyboard: .ascii)
                        TextField("SSH Host or IP Address", text: $draft.sshHost)
                            .textContentType(.URL)
                            .accessibilityIdentifier("credential-ssh-host")
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                    case .apiKey:
                        TextField("Account or Key Label (Optional)", text: $draft.username)
                            .textContentType(.username)
                            .accessibilityIdentifier("credential-api-key-label")
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.asciiCapable)
                            #endif

                        secretField(
                            title: "API Key",
                            value: $draft.apiKey,
                            accessibilityIdentifier: "credential-api-key",
                            showsGenerator: false
                        )

                        TextField("API Endpoint (Optional)", text: $draft.apiEndpoint)
                            .textContentType(.URL)
                            .accessibilityIdentifier("credential-api-endpoint")
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                    }
                }

                Section("Notes") {
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 100)
                }

                if let error = store.errorMessage {
                    Section {
                        ErrorMessageView(message: error)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(draft.name.isEmpty ? "New Credential" : "Edit Credential")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.saveCredential(credentialForSaving) {
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
        .frame(minWidth: 360, idealWidth: 520, minHeight: 440, idealHeight: 620)
        .sheet(isPresented: $isPresentingGenerator) {
            PasswordGeneratorView(initialAllowedSymbols: generatorSymbolOverride) { generatedPassword, allowedSymbols in
                draft.password = generatedPassword
                if draft.kind == .website {
                    draft.allowedPasswordSymbols = siteOverride(from: allowedSymbols)
                }
                isSecretRevealed = true
            }
        }
        .privacySensitive()
    }

    private var canSave: Bool {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        switch draft.kind {
        case .website:
            return true
        case .ssh:
            return SSHLauncher.connection(
                username: draft.username,
                host: draft.sshHost,
                customCommand: draft.sshCommand
            ) != nil
        case .apiKey:
            return !draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var credentialForSaving: Credential {
        var credential = draft
        if credential.kind == .website {
            credential.allowedPasswordSymbols = siteOverride(from: credential.allowedPasswordSymbols)
        }
        return credential
    }

    private var generatorSymbolOverride: String? {
        guard draft.kind == .website else { return nil }
        let symbols = PasswordGenerator.normalizedSymbols(draft.allowedPasswordSymbols)
        return symbols.isEmpty ? nil : symbols
    }

    private func siteOverride(from value: String) -> String {
        let symbols = PasswordGenerator.normalizedSymbols(value)
        return symbols == PasswordGeneratorOptions.defaultSymbols ? "" : symbols
    }

    @ViewBuilder
    private func loginFields(usernameLabel: String, usernameKeyboard: UsernameKeyboard) -> some View {
        TextField(usernameLabel, text: $draft.username)
            .textContentType(.username)
            .accessibilityIdentifier("credential-username")
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(usernameKeyboard == .email ? .emailAddress : .asciiCapable)
            #endif

        secretField(
            title: "Password",
            value: $draft.password,
            accessibilityIdentifier: "credential-password",
            showsGenerator: true
        )
        .textContentType(.password)
    }

    private func secretField(
        title: String,
        value: Binding<String>,
        accessibilityIdentifier: String,
        showsGenerator: Bool
    ) -> some View {
        HStack {
            Group {
                if isSecretRevealed {
                    TextField(title, text: value)
                } else {
                    SecureField(title, text: value)
                }
            }
            .accessibilityIdentifier(accessibilityIdentifier)

            Button {
                isSecretRevealed.toggle()
            } label: {
                Image(systemName: isSecretRevealed ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isSecretRevealed ? "Hide \(title.lowercased())" : "Reveal \(title.lowercased())")

            if showsGenerator {
                Button {
                    isPresentingGenerator = true
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Generate strong password")
                .accessibilityIdentifier("generate-password-button")
            }
        }
    }
}
