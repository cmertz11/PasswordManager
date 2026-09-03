import SwiftUI

struct CloudConflictResolutionView: View {
    @Bindable var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var cloudMasterPassword = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Two encrypted vault copies could not be merged safely.", systemImage: "exclamationmark.icloud.fill")
                        .foregroundStyle(.orange)
                    Text("Editing is paused until you choose a known-good copy. Both encrypted copies have been retained.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("Keep This Device") {
                    Text("Replace the iCloud copy with the vault currently open on this device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Use This Device's Copy", systemImage: "laptopcomputer.and.iphone") {
                        Task {
                            if await store.resolveCloudConflictKeepingLocal() {
                                dismiss()
                            }
                        }
                    }
                    .disabled(store.isBusy)
                }

                Section("Use iCloud") {
                    SecureField("Master password for iCloud copy", text: $cloudMasterPassword)
                    Text("The iCloud copy is verified with its master password before it replaces the local vault. Biometric quick unlock will need to be enabled again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Use iCloud Copy", systemImage: "icloud.and.arrow.down") {
                        Task {
                            if await store.resolveCloudConflictUsingCloud(masterPassword: cloudMasterPassword) {
                                cloudMasterPassword = ""
                                dismiss()
                            }
                        }
                    }
                    .disabled(cloudMasterPassword.isEmpty || store.isBusy)
                }

                if let error = store.errorMessage {
                    Section { ErrorMessageView(message: error) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Resolve Sync Conflict")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Decide Later") {
                        store.isPresentingConflictResolution = false
                        dismiss()
                    }
                    .disabled(store.isBusy)
                }
            }
        }
        .frame(minWidth: 340, idealWidth: 540, minHeight: 520, idealHeight: 620)
        .interactiveDismissDisabled(store.isBusy)
        .privacySensitive()
    }
}
