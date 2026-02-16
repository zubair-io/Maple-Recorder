import Foundation

enum StorageLocation {
    private static let iCloudContainerId = "iCloud.com.just.maple.Maple-Recorder"

    static var recordingsURL: URL {
        if let iCloudURL = FileManager.default
            .url(forUbiquityContainerIdentifier: iCloudContainerId)?
            .appendingPathComponent("Documents").appendingPathComponent("recordings") {
            return iCloudURL
        }
        // Local fallback when iCloud is unavailable
        return FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("recordings")
    }

    static func ensureDirectoryExists() throws {
        let url = recordingsURL
        if !FileManager.default.fileExists(atPath: url.path()) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
