# PasswordManager: half-day MVP plan

## Outcome

Build a small, personal password manager from one SwiftUI codebase that runs on macOS, iPhone, and iPad. It will provide encrypted credential storage, simple search and editing, a cryptographically secure password generator, biometric quick unlock, encrypted iCloud sync, and an encrypted backup export.

This began as a four-hour MVP and is not a production-audited password manager. Treat changes as security-sensitive even when the source is public. Browser extensions, system Password AutoFill, sharing, and other expansion work are deliberately excluded.

## Accepted assumptions

- The same vault should sync among the owner's Mac, iPhone, and iPad.
- The owner has an Apple Developer Program account and uses the same iCloud account on all devices.
- Face ID or Touch ID provides quick unlock on supported devices; the master password always remains the recovery path.
- Distribution is intended for development and direct installation on registered devices, not through the App Store.
- The four-hour timebox is firm. If provisioning or CloudKit setup consumes unexpected time, cut optional polish before cutting encryption or its tests.

## MVP scope

### Must ship

- Create one vault protected by a confirmed master password.
- Add, edit, delete, search, and view credentials.
- Credential fields: name, username/email, password, website, and notes.
- Hide passwords by default; provide explicit reveal and copy actions.
- Generate random passwords with:
  - Default length 24; selectable range 12–64.
  - Uppercase, lowercase, digits, and symbols enabled by default.
  - An option to omit ambiguous characters.
  - At least one character from every selected character class.
  - Cryptographically secure random selection without modulo bias.
- Encrypt the vault before writing it to local disk or iCloud.
- Unlock with the master password on a new device, then optionally enable biometric quick unlock on that device.
- Lock immediately when the app moves to the background and provide a manual Lock command.
- Sync on unlock, foreground entry, and after changes; continue to work from the encrypted local cache while offline.
- Export the existing encrypted vault envelope as a backup file. No plaintext export.
- Show clear error states for wrong password, unavailable iCloud, sync conflict, corrupt/tampered vault, and failed save.

### Explicitly out of scope

- Browser extensions and system Password AutoFill credential-provider extensions.
- Passkeys, one-time-password generation, attachments, shared/family vaults, and multiple vaults.
- Password breach lookup, password-health dashboards, tags/folders, custom fields, and icons fetched from the web.
- Password import from other managers and plaintext CSV export.
- Account recovery or master-password reset. Losing the master password and every biometric-unlock device means losing access to the vault.
- App Store, TestFlight, a backend server, analytics, telemetry, or third-party SDKs.

## User experience

### First launch

1. Check the user's private CloudKit database for an existing encrypted vault.
2. If one exists, show **Unlock Existing Vault** and request its master password.
3. Otherwise show **Create Vault**, request and confirm a master password, explain that it cannot be recovered, create the vault, and offer Face ID/Touch ID.
4. Use a short master-password policy: at least 12 characters, allow spaces, and show guidance rather than arbitrary composition rules.

### Locked state

- A quiet screen with the app name, one biometric unlock button when available, a master-password fallback, and a concise error message area.
- Never reveal whether a failed master password was “close”; decryption either succeeds or fails.

### Main state

- Use `NavigationSplitView`: searchable credential list on the left and details on the right. It naturally collapses to stack navigation on iPhone.
- Put Add, Lock, and Settings in predictable toolbar locations.
- List rows contain only the credential name and username. Do not place passwords in list rows or notifications.
- The detail view has copy buttons beside username and password, a momentary reveal control, and Edit/Delete actions.
- The editor keeps only the five MVP fields visible. Put **Generate Password** beside the password field and present the generator in a compact sheet.
- Settings contains biometric-unlock status, iCloud sync status/last success, manual Sync Now, and encrypted backup export.

### Small privacy details

- Clear copied passwords after 30 seconds only if the pasteboard still contains the value placed there by this app.
- Cover sensitive UI before iOS/iPadOS creates an app-switcher snapshot.
- Never print, log, or include credential data, keys, master passwords, or plaintext vault contents in error descriptions.

## Technical design

### Project shape

- Create one SwiftUI multiplatform app target for macOS, iOS, and iPadOS, with shared model, service, and view code.
- Prefer current Swift concurrency (`async`/`await`) and keep mutable vault state isolated to `@MainActor` in `VaultStore`.
- Use Apple frameworks only: SwiftUI, Foundation, CryptoKit, Security, LocalAuthentication, CloudKit, and CommonCrypto.
- Set minimum OS versions to the oldest versions actually installed on the owner's three devices; do not pick them blindly before checking. Favor iOS/iPadOS 17 and macOS 14 or newer if the devices allow it.

Proposed source layout:

```text
PasswordManager/
  App/
    PasswordManagerApp.swift
    AppState.swift
  Models/
    Credential.swift
    VaultPayload.swift
    VaultEnvelope.swift
  Security/
    CryptoService.swift
    PasswordKDF.swift
    KeychainService.swift
    BiometricService.swift
    SecureRandom.swift
  Storage/
    LocalVaultStore.swift
    CloudVaultStore.swift
    VaultSyncService.swift
  Features/
    Lock/
    Credentials/
    Generator/
    Settings/
  Tests/
```

### Data model

```text
Credential
  id: UUID
  name: String
  username: String
  password: String
  website: String
  notes: String
  createdAt: Date
  updatedAt: Date

DeletionTombstone
  credentialID: UUID
  deletedAt: Date

VaultPayload
  schemaVersion: Int
  credentials: [Credential]
  tombstones: [DeletionTombstone]
```

The payload exists as decoded plaintext only while the vault is unlocked. Search is in memory; no plaintext database, index, cache, or preference is written to disk.

### Cryptographic envelope

Use envelope encryption so changing the master password only re-wraps a small random key rather than every credential:

1. Generate a random 256-bit vault data-encryption key (DEK) with `SecRandomCopyBytes` and check its status.
2. Derive a 256-bit key-encryption key (KEK) from the master password and a fresh random 128-bit salt using PBKDF2-HMAC-SHA256 via CommonCrypto.
3. Start at 600,000 PBKDF2 iterations, store the KDF name/salt/iteration count in the envelope, and benchmark once on the oldest device. Keep unlock near 250–500 ms; raise the stored count if the device comfortably permits it, never silently lower an existing vault's value.
4. Wrap the DEK with the KEK using AES-256-GCM and a fresh random nonce.
5. Encode `VaultPayload` with deterministic date/data settings, then encrypt it with the DEK using AES-256-GCM and a different fresh nonce.
6. Authenticate non-secret envelope identifiers as AES-GCM associated data so header substitution is detected.
7. On every save, use a new random payload nonce. Never reuse a nonce with the same key.

The versioned, Codable envelope contains only:

```text
formatVersion
vaultID
kdf { algorithm, salt, iterations }
wrappedDEK { nonce, ciphertext, tag }
payload { nonce, ciphertext, tag }
```

The master password is never stored. A wrong master password fails authenticated DEK unwrapping. A modified payload fails AES-GCM authentication and must be reported as corrupt/tampered without overwriting the last known-good local file.

### Keychain and biometrics

- After a successful master-password unlock, optionally store a local copy of the DEK as a generic-password Keychain item.
- Make the item non-synchronizable and device-only. Protect access with `SecAccessControl` using `biometryCurrentSet`, so biometric enrollment changes invalidate quick unlock.
- Use the data-protection Keychain on macOS as well as iOS/iPadOS.
- Biometric failure or an invalidated/missing item falls back to the master password, which can unwrap the DEK again and recreate the local biometric item.
- Clear the in-memory DEK and decoded payload when locking. Swift cannot guarantee complete zeroization of every copied value, so minimize copies and lifetimes rather than promising perfect memory erasure.

### Local persistence

- Store only the encoded `VaultEnvelope` in Application Support using atomic replacement.
- Keep the previous known-good encrypted file until the new file is fully written.
- Use file protection where supported and restrictive file permissions on macOS as defense in depth; application-level AES-GCM remains the primary protection.
- Store only non-secret settings such as biometric preference, last sync time, and a dirty-sync flag in `UserDefaults`.

### iCloud sync

- Use the app's private CloudKit database and one stable record ID for the encrypted envelope. The only app data field in CloudKit is an opaque `Data` blob; credential names, usernames, URLs, and notes never become CloudKit fields.
- Maintain the fetched record change tag and save with `ifServerRecordUnchanged` so a newer server version cannot be silently overwritten.
- Sync at unlock, app foreground, explicit Sync Now, and after a short debounce following a local save. Do not build push subscriptions in the MVP.
- On `serverRecordChanged`, decrypt the server and local payloads, merge by credential UUID using the newest `updatedAt`/`deletedAt`, re-encrypt with a fresh nonce, and retry once. Keep tombstones so deletion is not undone by an older device.
- If automatic merge or decryption fails, preserve both encrypted blobs, leave the vault locked or read-only, and ask the user to choose the known-good copy. Never choose by overwriting ciphertext blindly.
- If iCloud is signed out or unavailable, continue locally, show an Offline/Needs Sync status, and retry later.

This sync model intentionally optimizes for one owner editing a small vault on a few devices. Clock-based conflict resolution is acceptable for the MVP but is not a substitute for production-grade sync semantics.

### Password generator

- Obtain bytes from `SecRandomCopyBytes(kSecRandomDefault, ...)`, checking for `errSecSuccess`.
- Construct the enabled character-class pools, take at least one uniformly selected character from each selected pool, fill the remaining positions from the combined pool, and securely shuffle the result.
- Use rejection sampling when mapping random bytes to a pool index so modulo bias is avoided.
- Reject impossible settings and ensure the requested length is at least the number of enabled classes.
- Display an approximate entropy value based on length and pool size as guidance, not as a guarantee.
- Unit-test length, allowed characters, selected-class inclusion, ambiguous-character exclusion, and error cases.

## Four-hour implementation schedule

| Time | Deliverable |
|---|---|
| 0:00–0:20 | Select the installed full Xcode; create the multiplatform SwiftUI project; configure automatic signing, iCloud/CloudKit, Keychain, and Face ID usage description. Confirm all three run destinations. |
| 0:20–1:05 | Implement models, secure random helper, PBKDF2, AES-GCM envelope encryption, and crypto unit tests. Do not proceed until round-trip, wrong-password, and tamper tests pass. |
| 1:05–1:35 | Add atomic encrypted local storage, Keychain DEK storage, biometric unlock, app lock state, and background locking. |
| 1:35–2:30 | Build onboarding, locked screen, adaptive list/detail UI, search, CRUD editor, reveal/copy actions, and empty/error states. |
| 2:30–2:55 | Build the generator sheet, secure selection/shuffle, generator tests, and timed clipboard clearing. |
| 2:55–3:30 | Add private CloudKit single-record sync, offline status, change-tag protection, minimal merge/tombstone handling, and one sync test around the pure merge function. |
| 3:30–3:45 | Add encrypted file export, privacy cover, manual Lock/Sync commands, and final error handling. |
| 3:45–4:00 | Run tests and smoke-test on Mac, one iPhone, and one iPad; confirm create/edit/sync/unlock/export; record anything deferred. |

### Hard cut line

At four hours, keep the smallest secure vertical slice. Cut in this order if necessary:

1. Entropy display and visual polish.
2. Encrypted file export.
3. Automatic conflict merge; retain conflict detection and require an explicit user choice instead.
4. Timed clipboard clearing on macOS if the cross-platform pasteboard adapter is unfinished; keep copy explicit and secrets hidden.

Do **not** cut authenticated encryption, KDF hardening, atomic writes, background locking, wrong-password/tamper tests, or protection against silent CloudKit overwrite.

## Verification checklist

### Automated

- Encrypt/decrypt round trip preserves every field.
- The wrong master password cannot unwrap the DEK.
- A changed header, wrapped key, ciphertext byte, nonce, or tag is rejected.
- Two saves of identical plaintext produce different ciphertext.
- Generator meets length and class constraints across many generated samples.
- Delete tombstones beat older credentials; newer edits beat older edits.

### Manual on all three platforms

- Create a vault on device A, add a generated credential, and confirm it appears on devices B and C only after the master password is entered there.
- Confirm the CloudKit record contains only opaque encrypted bytes plus CloudKit-managed metadata.
- Enable biometrics independently on each device; verify master-password fallback after biometric cancellation and enrollment change.
- Background and reopen the app; verify it is locked and sensitive content is absent from the app-switcher snapshot.
- Work offline, make an edit, reconnect, and confirm sync status and eventual upload.
- Make overlapping edits on two devices and verify there is no silent data loss.
- Export a backup and confirm it contains no searchable credential plaintext.
- Search logs and project files for known test credentials and master passwords.

## Direct installation

- Use automatic signing with the owner's Apple Developer team and register the iPhone/iPad through Xcode.
- During development, build and run directly to the Mac and attached devices. Enable Developer Mode on iPhone/iPad when prompted.
- For a reusable iPhone/iPad build, archive and export a development/ad hoc `.ipa` for registered devices, then install it with Xcode or Apple Configurator.
- For the Mac, run the signed development build locally or export/copy the app for personal use. App Store submission and review are not involved.

## Prerequisites and current workspace status

- The repository contains the multiplatform Xcode project, app sources, entitlements, shared schemes, and tests described above.
- Xcode 26.5 is installed and selected at `/Applications/Xcode.app/Contents/Developer`; `xcodebuild` and the bundled Swift 6.3.2 toolchain are ready for implementation.
- Signed builds require a developer-controlled Apple team, unique bundle identifiers, and a matching iCloud container. A fork must replace the maintainer-specific identifiers consistently across all three platforms before enabling CloudKit.

## Definition of done

The MVP is done when a credential generated and saved on one device is encrypted at rest, syncs as opaque ciphertext, can be unlocked on the other two devices with the master password, can subsequently use local biometrics, survives offline/relaunch behavior without plaintext persistence, and passes the crypto/generator tests and manual checks above.

## References

- [Apple: CryptoKit](https://developer.apple.com/documentation/cryptokit)
- [Apple: AES-GCM nonce uniqueness](https://developer.apple.com/documentation/cryptokit/aes/gcm/nonce)
- [Apple: cryptographically secure random bytes](https://developer.apple.com/documentation/security/1399291-secrandomcopybytes)
- [Apple: storing CryptoKit keys in the Keychain](https://developer.apple.com/documentation/cryptokit/storing-cryptokit-keys-in-the-keychain)
- [Apple: biometric authentication](https://developer.apple.com/documentation/localauthentication/logging-a-user-into-your-app-with-face-id-or-touch-id)
- [Apple: CloudKit private database](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)
- [Apple: CloudKit save-if-unchanged policy](https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/recordsavepolicy/ifserverrecordunchanged)
- [Apple: SwiftUI multiplatform app structure](https://developer.apple.com/documentation/swiftui/food-truck-building-a-swiftui-multiplatform-app)
- [Apple: direct distribution to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)
- [OWASP: Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
