import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
enum ClipboardService {
    static func copySecret(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.setItems(
            [["public.utf8-plain-text": value]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(30)
            ]
        )
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        let changeCount = pasteboard.changeCount
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            if pasteboard.changeCount == changeCount {
                pasteboard.clearContents()
            }
        }
        #endif
    }
}
