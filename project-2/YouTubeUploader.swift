
import Foundation
import UIKit

/// Uploads videos to a fixed company YouTube channel using OAuth2 credentials.
/// Videos are uploaded as unlisted via the YouTube Data API v3 resumable upload protocol.
final class YouTubeUploader {

    // MARK: - Credentials (replace with real values)

    private let clientID = "REDACTED_CLIENT_ID"
    private let clientSecret = "REDACTED_CLIENT_SECRET"
    private let refreshToken = "REDACTED_REFRESH_TOKEN"

    // MARK: - Upload

    /// Called on the main actor whenever the upload step changes.
    var onStatusUpdate: ((String) -> Void)?

    /// Uploads a video file to YouTube with the given title.
    /// Returns the YouTube video URL (e.g. "https://youtu.be/VIDEO_ID").
    func upload(fileURL: URL, title: String) async throws -> String {
        log("Starting upload for: \(fileURL.lastPathComponent)")
        status("Refreshing token...")

        let accessToken = try await refreshAccessToken()
        log("Access token obtained")

        status("Reading file...")
        let fileData = try Data(contentsOf: fileURL)
        let sizeMB = Double(fileData.count) / 1_048_576
        log("File loaded: \(String(format: "%.1f", sizeMB)) MB")

        status("Initiating upload...")
        let uploadURL = try await initiateResumableUpload(
            accessToken: accessToken,
            title: title,
            fileSize: fileData.count
        )
        log("Upload URI received")

        status("Uploading \(String(format: "%.1f", sizeMB)) MB...")
        let videoID = try await uploadFileData(
            fileData,
            to: uploadURL,
            accessToken: accessToken
        )
        log("Upload complete! Video ID: \(videoID)")
        status("Done!")

        return "https://youtu.be/\(videoID)"
    }

    private func log(_ message: String) {
        print("[YouTubeUploader] \(message)")
    }

    private func status(_ message: String) {
        log("Status: \(message)")
        let callback = onStatusUpdate
        Task { @MainActor in
            callback?(message)
        }
    }

    // MARK: - OAuth Token Refresh

    private func refreshAccessToken() async throws -> String {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        request.httpBody = body
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        log("POST \(url) ...")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        log("Token response: HTTP \(httpResponse?.statusCode ?? -1)")

        guard httpResponse?.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            log("Token refresh FAILED: \(message)")
            throw YouTubeUploadError.tokenRefreshFailed(message)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let accessToken = json?["access_token"] as? String else {
            log("Token refresh FAILED: no access_token in JSON")
            throw YouTubeUploadError.tokenRefreshFailed("No access_token in response")
        }

        return accessToken
    }

    // MARK: - Resumable Upload

    private func initiateResumableUpload(
        accessToken: String,
        title: String,
        fileSize: Int
    ) async throws -> URL {
        let endpoint = "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("\(fileSize)", forHTTPHeaderField: "X-Upload-Content-Length")
        request.setValue("video/*", forHTTPHeaderField: "X-Upload-Content-Type")

        let metadata: [String: Any] = [
            "snippet": [
                "title": title,
                "description": "Uploaded from app"
            ],
            "status": [
                "privacyStatus": "unlisted"
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata)

        log("POST resumable upload init...")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        log("Init response: HTTP \(httpResponse?.statusCode ?? -1)")

        guard httpResponse?.statusCode == 200,
              let locationString = httpResponse?.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: locationString) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            log("Upload init FAILED: \(message)")
            throw YouTubeUploadError.uploadInitFailed(message)
        }

        return uploadURL
    }

    private func uploadFileData(
        _ fileData: Data,
        to uploadURL: URL,
        accessToken: String
    ) async throws -> String {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("video/*", forHTTPHeaderField: "Content-Type")
        request.setValue("\(fileData.count)", forHTTPHeaderField: "Content-Length")

        // Request background execution time for large uploads
        let backgroundTaskID = await UIApplication.shared.beginBackgroundTask()

        log("PUT file data (\(fileData.count) bytes)...")
        let (data, response) = try await URLSession.shared.upload(for: request, from: fileData)

        await UIApplication.shared.endBackgroundTask(backgroundTaskID)

        let httpResponse = response as? HTTPURLResponse
        log("Upload response: HTTP \(httpResponse?.statusCode ?? -1)")

        guard httpResponse?.statusCode == 200 || httpResponse?.statusCode == 201 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            log("Upload FAILED: \(message)")
            throw YouTubeUploadError.uploadFailed(message)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let videoID = json?["id"] as? String else {
            log("Upload FAILED: no video ID in response JSON")
            throw YouTubeUploadError.uploadFailed("No video ID in response")
        }

        log("Video ID: \(videoID)")
        return videoID
    }
}

// MARK: - Errors

enum YouTubeUploadError: LocalizedError {
    case tokenRefreshFailed(String)
    case uploadInitFailed(String)
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .tokenRefreshFailed(let detail): "Token refresh failed: \(detail)"
        case .uploadInitFailed(let detail): "Upload init failed: \(detail)"
        case .uploadFailed(let detail): "Upload failed: \(detail)"
        }
    }
}
