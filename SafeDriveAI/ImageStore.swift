// Creates the folders and file names for paired front and back JPEGs.
// The app prepares the directories at launch.
// DualCameraSession writes a pair when a still is captured.

import Foundation

/// Folders and file names for paired front and back JPEGs. The app creates the folders at launch, and `DualCameraSession` writes a pair when a still is captured.
enum ImageStore {
    static let frontFolderName = "Front_Images"
    static let backFolderName = "Back_Images"

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var frontDirectory: URL {
        documentsDirectory.appendingPathComponent(frontFolderName, isDirectory: true)
    }

    static var backDirectory: URL {
        documentsDirectory.appendingPathComponent(backFolderName, isDirectory: true)
    }

    static func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: frontDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backDirectory, withIntermediateDirectories: true)
    }

    static func fileName(capturedAt date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "\(formatter.string(from: date)).jpg"
    }

    static func savePair(frontJPEG: Data, backJPEG: Data, fileName: String) throws {
        try prepareDirectories()
        try frontJPEG.write(to: frontDirectory.appendingPathComponent(fileName), options: .atomic)
        try backJPEG.write(to: backDirectory.appendingPathComponent(fileName), options: .atomic)
    }
}
