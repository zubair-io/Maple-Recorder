import Foundation

enum StorageLocation {
    static var recordingsURL: URL {
        if let iCloudURL = FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents").appendingPathComponent("recordings") {
            return iCloudURL
        }
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
