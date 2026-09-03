import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var isExporting = false
    @State private var exportDocument = EncryptedVaultDocument(data: Data())
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Unlock") {
                    if store.biometricAvailability.isAvailable {
                        LabeledContent(
                            "\(store.biometricAvailability.name) quick unlock",
                            value: store.biometricQuickUnlockEnabled ? "On" : "Off"
                        )
                        Button(store.biometricQuickUnlockEnabled ? "Turn Off" : "Turn On") {
                            updateBiometrics(!store.biometricQuickUnlockEnabled)
                        }
                    } else {
                        Label("Biometric unlock is unavailable", systemImage: "touchid")
                            .foregroundStyle(.secondary)
                    }
                    Text("The master password always remains available and is required on a new device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if store.isCloudSyncEnabled {
                    Section("iCloud") {
                        LabeledContent("Status", value: store.syncStatus.label)
                        if let date = store.lastSuccessfulSyncDate {
                            LabeledContent("Last successful sync") {
                                Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                            }
                        }
                        Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                            Task {
                                await store.syncNow()
                                localError = nil
                            }
                        }
                        .disabled(store.syncStatus == .syncing)
                    }
                } else {
                    Section("Storage") {
                        Label("Local-only build", systemImage: "internaldrive")
                        Text("This build stores the encrypted vault on this device and does not connect to CloudKit.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if store.hasUnresolvedCloudConflict {
                    Section("Sync Conflict") {
                        Label("Editing is paused until you choose a known-good encrypted copy.", systemImage: "exclamationmark.icloud")
                            .foregroundStyle(.orange)
                        Button("Resolve Conflict…") {
                            dismiss()
                            store.isPresentingConflictResolution = true
                        }
                    }
                }

                Section("Backup") {
                    Button("Export Encrypted Backup…", systemImage: "square.and.arrow.up") {
                        prepareExport()
                    }
                    Text("The backup uses the same encrypted vault envelope. No plaintext export is available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let message = localError ?? store.errorMessage {
                    Section { ErrorMessageView(message: message) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, idealWidth: 520, minHeight: 420, idealHeight: 560)
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .passwordManagerVault,
            defaultFilename: "PasswordManager-Backup"
        ) { result in
            if case .failure = result {
                localError = "The encrypted backup could not be exported."
            }
        }
    }

    private func updateBiometrics(_ enabled: Bool) {
        do {
            try store.setBiometricQuickUnlock(enabled)
            localError = nil
        } catch {
            localError = "Biometric quick unlock could not be updated. The master password still works."
        }
    }

    private func prepareExport() {
        do {
            exportDocument = EncryptedVaultDocument(data: try store.encryptedBackupData())
            isExporting = true
            localError = nil
        } catch {
            localError = "The encrypted backup could not be prepared."
        }
    }
}

struct EncryptedVaultDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.passwordManagerVault] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static let passwordManagerVault = UTType(exportedAs: "\(AppConfiguration.bundleIdentifier).vault")
}
