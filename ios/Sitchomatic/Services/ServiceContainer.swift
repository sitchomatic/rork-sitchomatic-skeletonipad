import Foundation
import Observation

@Observable
@MainActor
class ServiceContainer {
    static let shared = ServiceContainer()

    let proxyRotation: ProxyRotationService
    let networkSessionFactory: NetworkSessionFactory
    let deviceProxy: DeviceProxyService
    let debugLogger: DebugLogger
    let fingerprintValidation: FingerprintValidationService
    let screenshotCache: ScreenshotCache

    init(
        proxyRotation: ProxyRotationService? = nil,
        networkSessionFactory: NetworkSessionFactory? = nil,
        deviceProxy: DeviceProxyService? = nil,
        debugLogger: DebugLogger? = nil,
        fingerprintValidation: FingerprintValidationService? = nil,
        screenshotCache: ScreenshotCache? = nil
    ) {
        self.proxyRotation = proxyRotation ?? .shared
        self.networkSessionFactory = networkSessionFactory ?? .shared
        self.deviceProxy = deviceProxy ?? .shared
        self.debugLogger = debugLogger ?? .shared
        self.fingerprintValidation = fingerprintValidation ?? .shared
        self.screenshotCache = screenshotCache ?? .shared
    }
}
