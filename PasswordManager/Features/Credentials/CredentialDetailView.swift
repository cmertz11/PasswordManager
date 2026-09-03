import SwiftUI

struct CredentialDetailView: View {
    @Bindable var store: VaultStore
    let credential: Credential
    @State private var isSecretRevealed = false
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var isShowingSSHError = false
    @State private var copiedField: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    headerIcon
                    Text(credential.name.isEmpty ? "Untitled" : credential.name)
                        .font(.largeTitle.bold())
                    switch credential.kind {
                    case .website:
                        if let websiteURL {
                            Link(destination: websiteURL) {
                                Label(displayWebsite, systemImage: "arrow.up.right.square")
                            }
                        }
                    case .ssh:
                        if sshConnection != nil {
                            Label(
                                displaySSHDestination,
                                systemImage: customSSHCommand == nil ? "network" : "terminal"
                            )
                                .foregroundStyle(.secondary)
                        }
                    case .apiKey:
                        if let apiEndpointURL {
                            Link(destination: apiEndpointURL) {
                                Label(displayAPIEndpoint, systemImage: "arrow.up.right.square")
                            }
                        } else if !credential.apiEndpoint.isEmpty {
                            Label(credential.apiEndpoint, systemImage: "network")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(spacing: 0) {
                    switch credential.kind {
                    case .website:
                        DetailField(
                            title: "Username",
                            value: credential.username,
                            concealed: false,
                            copied: copiedField == "Username",
                            onCopy: { copy(credential.username, field: "Username") }
                        )
                        Divider()
                        DetailField(
                            title: "Password",
                            value: credential.password,
                            concealed: !isSecretRevealed,
                            copied: copiedField == "Password",
                            onCopy: { copy(credential.password, field: "Password") },
                            onReveal: { isSecretRevealed.toggle() }
                        )
                        if !credential.allowedPasswordSymbols.isEmpty {
                            Divider()
                            DetailField(
                                title: "Allowed Password Symbols",
                                value: credential.allowedPasswordSymbols,
                                concealed: false,
                                copied: copiedField == "Allowed Password Symbols",
                                onCopy: { copy(credential.allowedPasswordSymbols, field: "Allowed Password Symbols") }
                            )
                        }
                    case .ssh:
                        if let customSSHCommand {
                            DetailField(
                                title: "Connection Command",
                                value: customSSHCommand,
                                concealed: false,
                                copied: copiedField == "Connection Command",
                                onCopy: { copy(customSSHCommand, field: "Connection Command") }
                            )
                            Divider()
                        }
                        DetailField(
                            title: "SSH Host",
                            value: credential.sshHost,
                            concealed: false,
                            copied: copiedField == "SSH Host",
                            onCopy: { copy(credential.sshHost, field: "SSH Host") }
                        )
                        Divider()
                        DetailField(
                            title: "Username",
                            value: credential.username,
                            concealed: false,
                            copied: copiedField == "Username",
                            onCopy: { copy(credential.username, field: "Username") }
                        )
                        Divider()
                        DetailField(
                            title: "Password",
                            value: credential.password,
                            concealed: !isSecretRevealed,
                            copied: copiedField == "Password",
                            onCopy: { copy(credential.password, field: "Password") },
                            onReveal: { isSecretRevealed.toggle() }
                        )
                    case .apiKey:
                        DetailField(
                            title: "Account or Key Label",
                            value: credential.username,
                            concealed: false,
                            copied: copiedField == "Account or Key Label",
                            onCopy: { copy(credential.username, field: "Account or Key Label") }
                        )
                        Divider()
                        DetailField(
                            title: "API Key",
                            value: credential.apiKey,
                            concealed: !isSecretRevealed,
                            copied: copiedField == "API Key",
                            onCopy: { copy(credential.apiKey, field: "API Key") },
                            onReveal: { isSecretRevealed.toggle() }
                        )
                        Divider()
                        DetailField(
                            title: "API Endpoint",
                            value: credential.apiEndpoint,
                            concealed: false,
                            copied: copiedField == "API Endpoint",
                            onCopy: { copy(credential.apiEndpoint, field: "API Endpoint") }
                        )
                    }
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))

                if !credential.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        Text(credential.notes)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle(credential.name)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.isPresentingEditor = true
                } label: {
                    Label("Add Credential", systemImage: "plus")
                }
                .disabled(store.hasUnresolvedCloudConflict)
                .accessibilityIdentifier("add-credential-button")

                Button {
                    store.isPresentingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("settings-button")

                #if os(macOS)
                if credential.kind == .ssh {
                    Button("Open SSH", systemImage: "terminal") {
                        openSSH()
                    }
                    .disabled(sshConnection == nil)
                    .accessibilityIdentifier("open-ssh-button")
                }
                #endif

                Button("Edit", systemImage: "pencil") {
                    isEditing = true
                }
                .disabled(store.hasUnresolvedCloudConflict)
                .accessibilityIdentifier("edit-credential-button")
                Button("Delete", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
                .disabled(store.hasUnresolvedCloudConflict)
                .accessibilityIdentifier("delete-credential-button")
            }
        }
        .sheet(isPresented: $isEditing) {
            CredentialEditorView(store: store, credential: credential)
        }
        .confirmationDialog(
            "Delete \(credential.name.isEmpty ? "this credential" : credential.name)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                _ = store.deleteCredential(id: credential.id)
            }
            .accessibilityIdentifier("confirm-delete-button")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletion will be saved to the encrypted vault.")
        }
        .alert("Unable to Open SSH", isPresented: $isShowingSSHError) {
            Button("OK") {}
        } message: {
            Text("Enter a custom SSH command or a valid SSH host or IP address, then try again.")
        }
    }

    private var websiteURL: URL? {
        webURL(from: credential.website)
    }

    private var apiEndpointURL: URL? {
        webURL(from: credential.apiEndpoint)
    }

    private func webURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    private var displayWebsite: String {
        websiteURL?.host() ?? credential.website
    }

    private var displayAPIEndpoint: String {
        apiEndpointURL?.host() ?? credential.apiEndpoint
    }

    @ViewBuilder
    private var headerIcon: some View {
        switch credential.kind {
        case .website:
            WebsiteIconView(website: credential.website, size: 36)
        case .ssh:
            Image(systemName: "terminal")
                .font(.title)
                .foregroundStyle(.tint)
        case .apiKey:
            Image(systemName: "key.horizontal.fill")
                .font(.title)
                .foregroundStyle(.tint)
        }
    }

    private var sshConnection: SSHLauncher.Connection? {
        SSHLauncher.connection(
            username: credential.username,
            host: credential.sshHost,
            customCommand: credential.sshCommand
        )
    }

    private var displaySSHDestination: String {
        if let customSSHCommand {
            return customSSHCommand
        }
        let username = credential.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = credential.sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return username.isEmpty ? host : "\(username)@\(host)"
    }

    private var customSSHCommand: String? {
        credential.sshCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : credential.sshCommand
    }

    #if os(macOS)
    private func openSSH() {
        if !SSHLauncher.openTerminal(
            username: credential.username,
            host: credential.sshHost,
            customCommand: credential.sshCommand
        ) {
            isShowingSSHError = true
        }
    }
    #endif

    private func copy(_ value: String, field: String) {
        guard !value.isEmpty else { return }
        ClipboardService.copySecret(value)
        copiedField = field
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if copiedField == field { copiedField = nil }
        }
    }
}

private struct DetailField: View {
    let title: String
    let value: String
    let concealed: Bool
    let copied: Bool
    let onCopy: () -> Void
    var onReveal: (() -> Void)?

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value.isEmpty ? "Not set" : (concealed ? String(repeating: "•", count: min(max(value.count, 8), 18)) : value))
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
                    .font(concealed ? .body.monospaced() : .body)
            }
            Spacer()
            if let onReveal, !value.isEmpty {
                Button(action: onReveal) {
                    Image(systemName: concealed ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(concealed ? "Reveal \(title.lowercased())" : "Hide \(title.lowercased())")
            }
            Button(action: onCopy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .disabled(value.isEmpty)
            .accessibilityLabel(copied ? "Copied" : "Copy \(title.lowercased())")
        }
        .padding(16)
    }
}
