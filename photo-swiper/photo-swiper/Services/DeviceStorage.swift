import Foundation

/// The device's storage, for the dashboard's "until this iPhone is full" forecast.
struct DeviceStorage: Equatable, Codable, Sendable {
    var total: Int64
    /// What's free for things the user asks for, which is what a new photo competes for.
    var available: Int64
}

/// Reads the device's storage. Behind a protocol so tests and mocks never depend on the real disk.
protocol DeviceStorageReading: Sendable {
    func current() -> DeviceStorage?
}

/// The volume the app lives on. A required-reason API: `PrivacyInfo.xcprivacy` declares it as
/// DiskSpace, reason 85F4.1 (shown to the user). It's read on the device and never sent anywhere.
struct VolumeStorageReader: DeviceStorageReading {
    func current() -> DeviceStorage? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL.homeDirectory.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DeviceStorage(total: Int64(total), available: available)
    }
}

#if DEBUG
/// A 128 GB iPhone with 18 GB free.
struct MockDeviceStorage: DeviceStorageReading {
    var storage = DeviceStorage(total: 128_000_000_000, available: 18_000_000_000)

    func current() -> DeviceStorage? { storage }
}
#endif
