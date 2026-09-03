import Foundation
import ImageIO
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum WebsiteIconSource {
    static func candidateURLs(for website: String) -> [URL] {
        let trimmed = website.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host,
              !host.isEmpty else { return [] }

        components.scheme = "https"
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil

        return ["/apple-touch-icon.png", "/favicon.ico"].compactMap { path in
            components.path = path
            return components.url
        }
    }
}

struct WebsiteIconView: View {
    let website: String
    var size: CGFloat = 24
    @State private var iconData: Data?

    var body: some View {
        Group {
            if let iconImage {
                iconImage
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.16)
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: size, height: size)
        .background(.quinary, in: RoundedRectangle(cornerRadius: size * 0.2))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        .task(id: website) {
            iconData = nil
            iconData = await WebsiteIconLoader.shared.iconData(for: website)
        }
        .accessibilityHidden(true)
    }

    private var iconImage: Image? {
        guard let iconData else { return nil }
        #if os(iOS)
        guard let image = UIImage(data: iconData) else { return nil }
        return Image(uiImage: image)
        #elseif os(macOS)
        guard let image = NSImage(data: iconData) else { return nil }
        return Image(nsImage: image)
        #endif
    }
}

private actor WebsiteIconLoader {
    static let shared = WebsiteIconLoader()

    private enum CachedIcon {
        case data(Data)
        case unavailable
    }

    private static let maximumIconSize = 2 * 1_024 * 1_024
    private var cache: [String: CachedIcon] = [:]
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 10
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func iconData(for website: String) async -> Data? {
        let candidates = WebsiteIconSource.candidateURLs(for: website)
        guard let firstCandidate = candidates.first else { return nil }
        let cacheKey = firstCandidate.deletingLastPathComponent().absoluteString.lowercased()

        if let cached = cache[cacheKey] {
            switch cached {
            case .data(let data): return data
            case .unavailable: return nil
            }
        }

        for url in candidates {
            guard !Task.isCancelled else { return nil }
            var request = URLRequest(url: url)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            request.setValue("PasswordManager/1.0", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      data.count <= Self.maximumIconSize,
                      Self.isSupportedImage(data) else { continue }
                cache[cacheKey] = .data(data)
                return data
            } catch is CancellationError {
                return nil
            } catch {
                continue
            }
        }

        cache[cacheKey] = .unavailable
        return nil
    }

    private static func isSupportedImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }
}
