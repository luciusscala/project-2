
import AVFoundation
import Foundation
import SwiftData
import UIKit

/// Manages persistent storage for recorded videos.
///
/// Videos are stored in Application Support/Videos with iCloud backup disabled.
/// Thumbnails are generated once at save time and stored in Application Support/Thumbnails.
/// Metadata is persisted via SwiftData. The exposed `modelContainer` should be
/// passed to `.modelContainer()` in the app entry point so SwiftUI views share
/// the same store.
final class VideoLibrary {

    let modelContainer: ModelContainer

    static let videosDirectory: URL = {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Videos", isDirectory: true)
    }()

    static let thumbnailsDirectory: URL = {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Thumbnails", isDirectory: true)
    }()

    init() {
        do {
            modelContainer = try ModelContainer(for: VideoRecord.self)
            try FileManager.default.createDirectory(at: Self.videosDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: Self.thumbnailsDirectory, withIntermediateDirectories: true)
        } catch {
            fatalError("VideoLibrary initialization failed: \(error)")
        }
    }

    /// Moves a recorded video from its temporary URL into persistent storage,
    /// generates a thumbnail, and saves metadata.
    /// Safe to call from any thread; each call creates its own short-lived ModelContext.
    func save(tempURL: URL, duration: TimeInterval) {
        let id = UUID()
        let fileName = "\(id.uuidString).mov"
        var destination = Self.videosDirectory.appendingPathComponent(fileName)

        do {
            try FileManager.default.moveItem(at: tempURL, to: destination)
            print("VideoLibrary: moved to \(destination.lastPathComponent)")

            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try destination.setResourceValues(values)

            generateThumbnail(for: destination, id: id)

            let context = ModelContext(modelContainer)
            context.insert(VideoRecord(id: id, duration: duration, fileName: fileName))
            try context.save()
        } catch {
            print("VideoLibrary.save error: \(error)")
        }
    }

    /// Returns the on-disk URL for a given video record.
    func videoURL(for record: VideoRecord) -> URL {
        Self.videosDirectory.appendingPathComponent(record.fileName)
    }

    /// Returns the on-disk URL for a video's thumbnail.
    func thumbnailURL(for record: VideoRecord) -> URL {
        let jpgName = record.fileName.replacingOccurrences(of: ".mov", with: ".jpg")
        return Self.thumbnailsDirectory.appendingPathComponent(jpgName)
    }

    // MARK: - Private

    private func generateThumbnail(for videoURL: URL, id: UUID) {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let thumbURL = Self.thumbnailsDirectory.appendingPathComponent("\(id.uuidString).jpg")
            guard let jpgData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7) else {
                print("Thumbnail: JPEG encoding failed")
                return
            }
            try jpgData.write(to: thumbURL)
            print("Thumbnail saved: \(thumbURL.lastPathComponent)")
        } catch {
            print("Thumbnail generation failed: \(error)")
            print("  videoURL exists: \(FileManager.default.fileExists(atPath: videoURL.path()))")
        }
    }
}
