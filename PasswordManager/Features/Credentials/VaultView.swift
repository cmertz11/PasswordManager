import SwiftUI

struct VaultView: View {
    @Bindable var store: VaultStore

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedCredentialID) {
                ForEach(store.filteredCredentials) { credential in
                    NavigationLink(value: credential.id) {
                        CredentialRow(credential: credential)
                    }
                }
            }
            .overlay {
                if store.filteredCredentials.isEmpty {
                    ContentUnavailableView(
                        store.searchText.isEmpty ? "No Credentials" : "No Results",
                        systemImage: store.searchText.isEmpty ? "key" : "magnifyingglass",
                        description: Text(store.searchText.isEmpty ? "Add your first credential to the encrypted vault." : "Try a different search.")
                    )
                }
            }
            .navigationTitle("Passwords")
            #if os(iOS)
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
                }
            }
            #endif
            .searchable(text: $store.searchText, prompt: "Search credentials")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    if store.hasUnresolvedCloudConflict {
                        Label("Sync conflict — editing paused", systemImage: "exclamationmark.icloud")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Resolve") {
                            store.isPresentingConflictResolution = true
                        }
                        .buttonStyle(.plain)
                        .font(.caption.bold())
                    } else {
                        Label(store.syncStatus.label, systemImage: "lock.icloud")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Lock", systemImage: "lock") {
                        store.lock()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .accessibilityIdentifier("lock-vault-button")
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        } detail: {
            if let credential = store.selectedCredential {
                CredentialDetailView(store: store, credential: credential)
                    .id(credential.revision)
            } else {
                ContentUnavailableView(
                    "Select a Credential",
                    systemImage: "key.horizontal",
                    description: Text("Choose a login from the list or add a new one.")
                )
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
                    }
                }
            }
        }
        .sheet(isPresented: $store.isPresentingEditor) {
            CredentialEditorView(store: store, credential: nil)
        }
        .sheet(isPresented: $store.isPresentingSettings) {
            SettingsView(store: store)
        }
        .sheet(isPresented: $store.isPresentingConflictResolution) {
            CloudConflictResolutionView(store: store)
        }
        .alert(
            "PasswordManager",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { isPresented in
                    if !isPresented { store.errorMessage = nil }
                }
            )
        ) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "An unknown error occurred.")
        }
        .privacySensitive()
    }
}

private struct CredentialRow: View {
    let credential: Credential

    var body: some View {
        HStack(spacing: 10) {
            credentialIcon
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(credential.name.isEmpty ? "Untitled" : credential.name)
                    .font(.headline)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        switch credential.kind {
        case .website:
            return credential.username
        case .ssh:
            if !credential.sshCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return credential.sshCommand
            }
            return [credential.username, credential.sshHost]
                .filter { !$0.isEmpty }
                .joined(separator: " @ ")
        case .apiKey:
            return credential.username.isEmpty ? credential.apiEndpoint : credential.username
        }
    }

    @ViewBuilder
    private var credentialIcon: some View {
        switch credential.kind {
        case .website:
            WebsiteIconView(website: credential.website, size: 24)
        case .ssh:
            Image(systemName: "terminal")
                .foregroundStyle(.tint)
        case .apiKey:
            Image(systemName: "key.horizontal.fill")
                .foregroundStyle(.tint)
        }
    }
}
