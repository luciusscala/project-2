
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Query(sort: \VideoRecord.createdAt, order: .reverse) private var records: [VideoRecord]
    @Environment(\.dismiss) private var dismiss

    let videoLibrary: VideoLibrary

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView("No Videos", systemImage: "video.slash", description: Text("Recorded videos will appear here."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(records) { record in
                                NavigationLink {
                                    VideoPlayerView(record: record, videoLibrary: videoLibrary)
                                } label: {
                                    ThumbnailCell(record: record, videoLibrary: videoLibrary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
}

// MARK: - Thumbnail Cell

private struct ThumbnailCell: View {
    let record: VideoRecord
    let videoLibrary: VideoLibrary

    var body: some View {
        let thumbURL = videoLibrary.thumbnailURL(for: record)

        ZStack(alignment: .bottomTrailing) {
            Group {
                if let uiImage = UIImage(contentsOfFile: thumbURL.path(percentEncoded: false)) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.3)
                        .overlay {
                            Image(systemName: "video")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(minHeight: 120)
            .clipped()

            Text(formattedDuration(record.duration))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                .padding(4)
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
