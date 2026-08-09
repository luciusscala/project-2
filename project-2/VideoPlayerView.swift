
import AVKit
import SwiftUI

struct VideoPlayerView: View {
    let record: VideoRecord
    let videoLibrary: VideoLibrary

    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            if let player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.black
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.createdAt, style: .date)
                        .font(.subheadline)
                    Text(formattedDuration(record.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle(record.createdAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
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

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
