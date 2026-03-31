import Foundation
import UIKit

/// High-performance off-main-actor work dispatcher using Swift 6.2 strict concurrency.
enum ConcurrentWork {

    /// Off-load throwing work to a detached task at the given priority.
    @concurrent
    static func offload<T: Sendable>(priority: TaskPriority = .userInitiated, _ work: @Sendable @escaping () throws -> T) async throws -> T {
        try await Task.detached(priority: priority) { try work() }.value
    }

    /// Off-load non-throwing work to a detached task at the given priority.
    @concurrent
    static func offload<T: Sendable>(priority: TaskPriority = .userInitiated, _ work: @Sendable @escaping () -> T) async -> T {
        await Task.detached(priority: priority) { work() }.value
    }

    /// Compress a UIImage to JPEG data, scaling down to `maxDimension` if needed.
    @concurrent
    static func compressImageToData(_ image: UIImage, quality: CGFloat = 0.4, maxDimension: CGFloat = 800) async -> Data? {
        let size = image.size
        let sendableImage = image
        return await offload(priority: .utility) {
            let targetImage: UIImage
            if size.width > maxDimension || size.height > maxDimension {
                let scale = maxDimension / max(size.width, size.height)
                let newSize = CGSize(width: size.width * scale, height: size.height * scale)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
                targetImage = renderer.image { _ in
                    sendableImage.draw(in: CGRect(origin: .zero, size: newSize))
                }
            } else {
                targetImage = sendableImage
            }
            return targetImage.jpegData(compressionQuality: quality)
        }
    }

    /// Encode a `Sendable & Encodable` value to JSON `Data` off the main actor.
    @concurrent
    static func encodeJSON<T: Encodable & Sendable>(_ value: T, prettyPrint: Bool = false) async -> Data? {
        await offload(priority: .utility) {
            let encoder = JSONEncoder()
            if prettyPrint { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
            return try? encoder.encode(value)
        }
    }

    /// Decode JSON `Data` to a `Sendable & Decodable` type off the main actor.
    @concurrent
    static func decodeJSON<T: Decodable & Sendable>(_ type: T.Type, from data: Data) async -> T? {
        await offload(priority: .utility) {
            try? JSONDecoder().decode(type, from: data)
        }
    }

    /// Atomically write `Data` to a URL off the main actor.
    @concurrent
    static func writeDataAtomically(_ data: Data, to url: URL) async {
        await offload(priority: .utility) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
