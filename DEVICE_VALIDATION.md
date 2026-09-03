# Physical-device validation

Use throwaway values for this pass. Do not enter a real master password or real account credential until every check below behaves as expected.

The repository's `PasswordManagerUI` scheme already automates the local create/generate/edit/background-lock/unlock/delete journey in an isolated simulator vault. The steps below intentionally focus on signed physical devices, real biometrics, and the real private CloudKit database.

## Preparation

- Sign the Mac, iPhone, and iPad into the same iCloud account.
- Enable Developer Mode on iPhone and iPad, connect each device to Xcode once, and trust the Mac if prompted.
- In Xcode, confirm the `PasswordManager` scheme uses your development team, your unique bundle ID, and the matching CloudKit container configured for this build.
- Pick a unique test marker such as `PM-DEVICE-VALIDATION-2026`; use it only in the throwaway credential so plaintext searches are unambiguous.

## Device A: create and upload

1. Run the app on the Mac.
2. Create a vault with a throwaway master password of at least 12 characters and enable Touch ID if offered.
3. Add a credential named with the unique marker. Generate its password in the editor and save it.
4. Open Settings, choose **Sync Now**, and wait for **Synced** plus a last-successful-sync time.
5. Lock, unlock with Touch ID, cancel one biometric prompt, and confirm the master-password fallback still works.
6. Export an encrypted backup. Run `strings /path/to/backup.pmvault | grep 'PM-DEVICE-VALIDATION-2026'`; it must produce no match.

## Devices B and C: download and unlock

Repeat on the iPhone and iPad:

1. Run the signed app. It should show **Vault Locked**, not **Create Your Vault**.
2. Enter the master password once and confirm the marker credential appears.
3. Enable Face ID or Touch ID in Settings on that device.
4. Lock and verify biometric quick unlock works locally. Biometric enablement must not automatically carry to the other device.

## Privacy and lifecycle

On every platform:

1. Reveal a password, then background or deactivate the app. It must lock immediately.
2. Inspect the app-switcher/window preview; credential content must not be visible.
3. Copy a password, wait at least 30 seconds without changing the pasteboard, and confirm it is gone. Repeat while replacing the pasteboard yourself; PasswordManager must not erase the replacement value.
4. Verify passwords remain concealed after returning to a credential.

## Offline and merge behavior

1. Take the iPad offline, edit the throwaway credential, and confirm the status becomes **Offline — saved locally** while the edit survives a lock/unlock.
2. Reconnect, choose **Sync Now**, and confirm the edit reaches the Mac and iPhone.
3. Take two devices offline, make different edits to two different credentials, reconnect both, and confirm both edits survive.
4. For the explicit-conflict screen, install an independent throwaway vault into one device's local app container only if you are comfortable manipulating development data. On reconnect, editing must pause and the app must require **Use This Device's Copy** or a master-password-verified **Use iCloud Copy**. Both encrypted inputs should remain under Application Support `Conflicts`.

## CloudKit inspection

In CloudKit Console, select the development environment for the container configured in your build and inspect `EncryptedVault/primary-vault`:

- The application-defined data consists only of the `blob` bytes field.
- Credential name, username, website, notes, generated password, and test marker do not appear as queryable fields or plaintext.
- CloudKit-managed record metadata is expected.

## Pass criteria

The device pass is complete only when the generated credential travels A → B → C as opaque ciphertext, each device independently enables biometrics, offline changes converge without silent loss, every background transition locks, and the backup/CloudKit plaintext checks find no test marker.
