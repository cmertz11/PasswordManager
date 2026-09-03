import SwiftUI

struct PasswordGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var options: PasswordGeneratorOptions
    @State private var password = ""
    @State private var errorMessage: String?
    let onUse: (String, String) -> Void

    init(initialAllowedSymbols: String? = nil, onUse: @escaping (String, String) -> Void) {
        var options = PasswordGeneratorOptions()
        if let initialAllowedSymbols,
           !PasswordGenerator.normalizedSymbols(initialAllowedSymbols).isEmpty {
            options.allowedSymbols = initialAllowedSymbols
        }
        _options = State(initialValue: options)
        self.onUse = onUse
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Generated Password") {
                    Text(password)
                        .font(.system(.title3, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Generated password")
                        .accessibilityIdentifier("generated-password-value")

                    HStack {
                        Label("Approximately \(Int(PasswordGenerator.approximateEntropyBits(options: options))) bits", systemImage: "shield.lefthalf.filled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Regenerate", systemImage: "arrow.clockwise") {
                            regenerate()
                        }
                    }
                }

                Section("Length: \(options.length)") {
                    Slider(
                        value: Binding(
                            get: { Double(options.length) },
                            set: { options.length = Int($0.rounded()) }
                        ),
                        in: 12...64,
                        step: 1
                    )
                }

                Section("Characters") {
                    Toggle("Lowercase", isOn: $options.includesLowercase)
                    Toggle("Uppercase", isOn: $options.includesUppercase)
                    Toggle("Digits", isOn: $options.includesDigits)
                    Toggle("Symbols", isOn: $options.includesSymbols)
                    if options.includesSymbols {
                        TextField("Allowed symbols", text: $options.allowedSymbols)
                            .font(.body.monospaced())
                            .accessibilityIdentifier("allowed-symbols-field")
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            #endif

                        HStack {
                            Button("Website Friendly") {
                                options.allowedSymbols = PasswordGeneratorOptions.defaultSymbols
                            }
                            Button("Extended") {
                                options.allowedSymbols = PasswordGeneratorOptions.extendedSymbols
                            }
                            Spacer()
                        }
                        .buttonStyle(.borderless)

                        Text("Generated passwords will use only the symbols entered above. Spaces and duplicate symbols are ignored.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Avoid ambiguous characters", isOn: $options.omitsAmbiguousCharacters)
                }

                if let errorMessage {
                    Section { ErrorMessageView(message: errorMessage) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Strong Password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Password") {
                        onUse(password, PasswordGenerator.normalizedSymbols(options.allowedSymbols))
                        dismiss()
                    }
                    .disabled(password.isEmpty)
                    .accessibilityIdentifier("use-generated-password-button")
                }
            }
        }
        .frame(minWidth: 360, idealWidth: 500, minHeight: 480)
        .onAppear { regenerate() }
        .onChange(of: options) { _, _ in regenerate() }
        .privacySensitive()
    }

    private func regenerate() {
        do {
            password = try PasswordGenerator.generate(options: options)
            errorMessage = nil
        } catch PasswordGeneratorError.noCharacterClassesSelected {
            password = ""
            errorMessage = "Select at least one character group."
        } catch PasswordGeneratorError.noSymbolsAvailable {
            password = ""
            errorMessage = "Enter at least one allowed symbol, or turn Symbols off."
        } catch {
            password = ""
            errorMessage = "A secure password could not be generated."
        }
    }
}
