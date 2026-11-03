import Foundation
import AVFoundation
import CoreMedia

/// Duration / resolution / codec / audio characteristics via AVFoundation.
/// Loads only metadata, never media data itself.
enum MediaMetadata {
    static func isMediaFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audio)
    }

    static func extract(url: URL) async -> MediaInfo? {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.load(.tracks) else { return nil }
        let video = tracks.first { $0.mediaType == .video }
        let audio = tracks.first { $0.mediaType == .audio }
        guard video != nil || audio != nil else { return nil }

        var info = MediaInfo(isVideo: video != nil)
        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite && seconds > 0 { info.durationSeconds = seconds }
        }
        if let videoTrack = video {
            if let size = try? await videoTrack.load(.naturalSize) {
                info.pixelWidth = Int(abs(size.width))
                info.pixelHeight = Int(abs(size.height))
            }
            if let rate = try? await videoTrack.load(.estimatedDataRate) {
                info.bitrate = Int64(rate)
            }
            info.codec = await codec(of: videoTrack)
        }
        if let audioTrack = audio {
            if let descriptions = try? await audioTrack.load(.formatDescriptions) {
                for case let description as CMFormatDescription in descriptions {
                    if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description) {
                        info.sampleRate = asbd.pointee.mSampleRate
                        info.channels = Int(asbd.pointee.mChannelsPerFrame)
                    }
                }
            }
        }
        return info
    }

    private static func codec(of track: AVAssetTrack) async -> String? {
        guard let descriptions = try? await track.load(.formatDescriptions) else { return nil }
        for case let description as CMFormatDescription in descriptions {
            let subtype = CMFormatDescriptionGetMediaSubType(description)
            let bytes: [UInt8] = [
                UInt8(truncatingIfNeeded: subtype >> 24),
                UInt8(truncatingIfNeeded: subtype >> 16),
                UInt8(truncatingIfNeeded: subtype >> 8),
                UInt8(truncatingIfNeeded: subtype)
            ]
            if let text = String(bytes: bytes, encoding: .ascii), text.allSatisfy({ $0.isASCII }) {
                return text
            }
        }
        return nil
    }
}
