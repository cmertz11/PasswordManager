# Build configurations

PasswordManager has two app configurations. The default is intentionally local-only so a fresh clone does not require access to the maintainer's Apple Developer account or iCloud container.

| Scheme | Storage | Setup required |
| --- | --- | --- |
| `PasswordManager` | Encrypted vault on this device only | None for My Mac or an iOS/iPadOS simulator |
| `PasswordManagerCloudKit` | The same local encrypted vault plus private CloudKit sync | A development team, unique bundle ID, and associated CloudKit container |

The schemes select different build configurations and entitlements. Local-only builds do not contain an iCloud-container entitlement and do not create a CloudKit client. CloudKit builds embed the configured container identifier and enable the existing encrypted synchronization code.

## Local-only quick start

This is the easiest way to inspect or develop the app.

1. Clone the repository and open `PasswordManager.xcodeproj` in Xcode.
2. Select the `PasswordManager` scheme.
3. Select **My Mac** or an iPhone/iPad simulator.
4. Press **Run**.

No Apple development team or CloudKit container is needed for My Mac or a simulator. The public default bundle identifier is `com.example.PasswordManager`.

In the app, **Settings → Storage** displays **Local-only build**. The encrypted vault remains in the app's local sandbox. Website icons still require network access, and opening an SSH command still requires Terminal automation permission on macOS.

Build the local-only Mac app from Terminal:

```sh
xcodebuild -project PasswordManager.xcodeproj \
  -scheme PasswordManager \
  -destination 'platform=macOS,arch=arm64' \
  build
```

### Local-only installation on a physical device

A physical iPhone or iPad still requires normal Apple code signing:

1. Copy the example developer settings file:

   ```sh
   cp Configuration/DeveloperSettings.xcconfig.example \
     Configuration/DeveloperSettings.xcconfig
   ```

2. Set `DEVELOPMENT_TEAM` to your team ID and change `PASSWORD_MANAGER_BUNDLE_IDENTIFIER` to a unique reverse-DNS identifier.
3. Keep the `PasswordManager` scheme selected, choose the registered device, and press **Run**.

`DeveloperSettings.xcconfig` is ignored by Git, so personal signing values are not accidentally committed. The cloud-container value in that file is unused by the local-only scheme.

## CloudKit configuration

CloudKit setup requires an active Apple Developer Program membership with permission to configure identifiers, a device or simulator signed in to iCloud, and a unique container. Apple notes that the Account Holder or Admin role is required to configure the relevant identifiers.

1. Copy the settings template if you have not already done so:

   ```sh
   cp Configuration/DeveloperSettings.xcconfig.example \
     Configuration/DeveloperSettings.xcconfig
   ```

2. Replace all three example values:

   ```xcconfig
   DEVELOPMENT_TEAM = ABCDE12345
   PASSWORD_MANAGER_BUNDLE_IDENTIFIER = com.yourname.PasswordManager
   PASSWORD_MANAGER_CLOUD_CONTAINER_IDENTIFIER = iCloud.com.yourname.PasswordManager
   ```

3. In Apple Developer **Certificates, Identifiers & Profiles**, register an explicit App ID matching `PASSWORD_MANAGER_BUNDLE_IDENTIFIER`.
4. Create the exact iCloud container named by `PASSWORD_MANAGER_CLOUD_CONTAINER_IDENTIFIER`.
5. Enable iCloud with CloudKit support for the App ID and associate that container with it. If the App ID already had provisioning profiles, regenerate them after changing its capabilities.
6. Open the project, select `PasswordManagerCloudKit`, choose **My Mac**, a simulator, or a registered device, and press **Run**. Automatic signing uses the team and identifiers from the ignored settings file.
7. Confirm the runtime device is signed in to iCloud. **Settings → iCloud** in the app will show synchronization status and a **Sync Now** action.

Apple's current setup references are [Enabling CloudKit in Your App](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app), [Register an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id), [Create an iCloud container](https://developer.apple.com/help/account/identifiers/create-an-icloud-container), and [Enable app capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/).

Build the configured CloudKit app from Terminal:

```sh
xcodebuild -project PasswordManager.xcodeproj \
  -scheme PasswordManagerCloudKit \
  -destination 'platform=macOS,arch=arm64' \
  build
```

## Configuration reference

The committed files in `Configuration/` provide safe public defaults:

- `Shared.xcconfig` defines default identifiers and optionally includes the ignored developer settings.
- `App-Local.xcconfig` selects local-only entitlements and disables CloudKit at runtime.
- `App-CloudKit.xcconfig` selects CloudKit entitlements and embeds the configured container identifier.
- `Tests.xcconfig` and `UITests.xcconfig` derive test bundle identifiers from the app identifier.
- `AppInfo.plist` carries the selected configuration into the app at runtime.

The app's Keychain service and exported backup type are derived from the resolved bundle identifier. A maintainer-specific identifier is not compiled into the source.

## Switching between modes

When both schemes use the same bundle identifier, they also use the same local app container and encrypted vault. Running `PasswordManagerCloudKit` after using the local-only build therefore enables synchronization for that existing local vault. Make an encrypted backup before switching if the vault matters.

To keep experiments completely separate, use a different `PASSWORD_MANAGER_BUNDLE_IDENTIFIER` in a separate checkout or developer settings file. Deleting the app may also delete its sandboxed local vault, depending on the platform, so retain an encrypted backup.

## Troubleshooting

- **The local scheme asks for an iCloud container:** verify that `PasswordManager`, not `PasswordManagerCloudKit`, is selected and clean the build folder.
- **Signing reports that the App ID cannot support iCloud:** use an explicit App ID owned by a qualifying development team; a wildcard ID is not sufficient for this configuration.
- **The provisioning profile lacks iCloud entitlements:** associate the container with the App ID, then let Xcode refresh automatic signing or regenerate the profile.
- **The app reports that iCloud is unavailable:** confirm the runtime device is signed in to iCloud, iCloud Drive is enabled, and the container identifier exactly matches the developer settings.
- **Changes do not appear on another device:** both builds must use the same bundle/container configuration and both devices must be signed into the intended iCloud account.
