import Foundation
import UIKit

/// The "Contact support" email: a subject naming the app, and a footer with what support needs to know.
enum SupportMail {
    /// A mailto: link, or nil if `email` can't make one.
    static func url(
        email: String,
        appName: String = AppInfo.name,
        version: String = AppInfo.version,
        build: String = AppInfo.build,
        systemVersion: String,
        model: String
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: "\(appName) support"),
            URLQueryItem(name: "body", value: body(appName: appName, version: version, build: build,
                                                    systemVersion: systemVersion, model: model)),
        ]
        return components.url
    }

    /// Room to write at the top, then the details.
    static func body(appName: String, version: String, build: String, systemVersion: String, model: String) -> String {
        """



        ---
        \(appName) \(version) (build \(build))
        iOS \(systemVersion)
        \(model)
        """
    }

    /// The link for this device.
    @MainActor
    static func url(email: String) -> URL? {
        url(email: email, systemVersion: UIDevice.current.systemVersion, model: deviceModel)
    }

    /// The hardware identifier, e.g. "iPhone17,3". The simulator reports the device it stands in for.
    static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
