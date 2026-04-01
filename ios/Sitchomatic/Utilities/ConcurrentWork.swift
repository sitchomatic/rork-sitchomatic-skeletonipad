import Foundation
import UIKit

enum ConcurrentWork {

    static func offload<T: Sendable>(priority: TaskPriority = .userInitiated, _ work: @Sendable @escaping () throws -> T) async throws -> T {
        try await Task.detached(priority: priority) { try work() }.value
    }

    static func offload<T: Sendable>(priority: TaskPriority = .userInitiated, _ work: @Sendable @escaping () -> T) async -> T {
        await Task.detached(priority: priority) { work() }.value
    }

    static func compressImageToData(_ image: UIImage, quality: CGFloat = 0.4, maxDimension: CGFloat = 800) async -> Data? {
        let size = image.size
        let sendableImage = image
        return await offload(priority: .utility) {
            let targetImage: UIImage
            if size.width > maxDimension || size.height > maxDimension {
                let scale = maxDimension / max(size.width, size.height)
                let newSize = CGSize(width: size.width * scale, height: size.height * scale)
                let renderer = UIGraphicsImageRenderer(size: newSize)
                targetImage = renderer.image { _ in
                    sendableImage.draw(in: CGRect(origin: .zero, size: newSize))
                }
            } else {
                targetImage = sendableImage
            }
            return targetImage.jpegData(compressionQuality: quality)
        }
    }

    static func encodeJSON<T: Encodable & Sendable>(_ value: T, prettyPrint: Bool = false) async -> Data? {
        await offload(priority: .utility) {
            let encoder = JSONEncoder()
            if prettyPrint { encoder.outputFormatting = .prettyPrinted }
            return try? encoder.encode(value)
        }
    }

    static func decodeJSON<T: Decodable & Sendable>(_ type: T.Type, from data: Data) async -> T? {
        let dataCopy = data
        return await offload(priority: .utility) {
            try? JSONDecoder().decode(type, from: dataCopy)
        }
    }

    static func writeDataAtomically(_ data: Data, to url: URL) async {
        let dataCopy = data
        let urlCopy = url
        await offload(priority: .utility) {
            try? dataCopy.write(to: urlCopy, options: .atomic)
        }
    }
}
