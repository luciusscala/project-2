
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
    @State private var isUploading = false
    @State private var uploadStatus: String = ""
    @State private var uploadError: String?

    private let uploader = YouTubeUploader()

    var body: some View {
        VStack(spacing: 0) {
            if let player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.black
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
        .onAppear {
            let url = videoLibrary.videoURL(for: record)
            player = AVPlayer(url: url)
            player?.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    // MARK: - Subviews

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
            if let urlString = record.youtubeURL, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label("YouTube", systemImage: "link")
                        .font(.caption)
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
                if record.uploadStatus == "none" || record.uploadStatus == "failed" {
                    Button {
                        uploadVideo()
                    } label: {
                        Label("Upload to YouTube", systemImage: "icloud.and.arrow.up")
                    }
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Actions

    private func uploadVideo() {
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


