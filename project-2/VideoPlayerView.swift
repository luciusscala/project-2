
import AVKit
import SwiftData
import SwiftUI

struct VideoPlayerView: View {
    let record: VideoRecord
    let videoLibrary: VideoLibrary

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var showDeleteConfirmation = false
    @State private var showDeleteLocalConfirmation = false
    @State private var isUploading = false
    @State private var uploadStatus: String = ""
    @State private var uploadError: String?

    private let uploader = YouTubeUploader()

    var body: some View {
        VStack(spacing: 0) {
            if record.isLocalFileAvailable {
                if let player {
                    VideoPlayer(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Color.black
                }
            } else {
                // Local file deleted — show thumbnail with YouTube link
                cloudOnlyView
            }

            bottomBar
        }
        .overlay {
            if isUploading {
                uploadOverlay
            }
        }
        .navigationTitle(record.createdAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .alert("Delete Video?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                player?.pause()
                player = nil
                do {
                    try videoLibrary.delete(record: record, context: modelContext)
                } catch {
                    print("Failed to delete video: \(error)")
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete the video and all its data.")
        }
        .alert("Delete Local Copy?", isPresented: $showDeleteLocalConfirmation) {
            Button("Delete Local", role: .destructive) {
                player?.pause()
                player = nil
                do {
                    try videoLibrary.deleteLocalFile(record: record, context: modelContext)
                } catch {
                    print("Failed to delete local file: \(error)")
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The video file will be removed from this device. You can still watch it on YouTube.")
        }
        .onAppear {
            if record.isLocalFileAvailable {
                let url = videoLibrary.videoURL(for: record)
                player = AVPlayer(url: url)
                player?.play()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    // MARK: - Subviews

    private var cloudOnlyView: some View {
        VStack(spacing: 16) {
            let thumbURL = videoLibrary.thumbnailURL(for: record)
            if let uiImage = UIImage(contentsOfFile: thumbURL.path(percentEncoded: false)) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Color.black
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let urlString = record.youtubeURL, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label("Watch on YouTube", systemImage: "play.rectangle.fill")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.red, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal)
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.createdAt, style: .date)
                    .font(.subheadline)
                Text(formattedDuration(record.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let urlString = record.youtubeURL, record.isLocalFileAvailable {
                if let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label("YouTube", systemImage: "link")
                            .font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var uploadOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(uploadStatus.isEmpty ? "Uploading..." : uploadStatus)
                    .font(.headline)
                    .foregroundStyle(.white)
                if let uploadError {
                    Text(uploadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
        .ignoresSafeArea()
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                // Upload button
                if record.isLocalFileAvailable,
                   record.uploadStatus == "none" || record.uploadStatus == "failed" {
                    Button {
                        uploadVideo()
                    } label: {
                        Label("Upload to YouTube", systemImage: "icloud.and.arrow.up")
                    }
                }

                // Delete local copy (only if uploaded and local file exists)
                if record.uploadStatus == "uploaded", record.isLocalFileAvailable {
                    Button(role: .destructive) {
                        showDeleteLocalConfirmation = true
                    } label: {
                        Label("Delete Local Copy", systemImage: "internaldrive")
                    }
                }

                // Full delete
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Everywhere", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Actions

    private func uploadVideo() {
        guard record.isLocalFileAvailable else { return }
        isUploading = true
        uploadError = nil
        uploadStatus = "Starting..."
        record.uploadStatus = "uploading"

        let fileURL = videoLibrary.videoURL(for: record)
        let title = record.createdAt.formatted(date: .abbreviated, time: .shortened)

        uploader.onStatusUpdate = { step in
            uploadStatus = step
        }

        Task {
            do {
                let youtubeURL = try await uploader.upload(fileURL: fileURL, title: title)
                record.youtubeURL = youtubeURL
                record.uploadStatus = "uploaded"
                try? modelContext.save()
            } catch {
                record.uploadStatus = "failed"
                uploadError = error.localizedDescription
                try? modelContext.save()
            }
            isUploading = false
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
