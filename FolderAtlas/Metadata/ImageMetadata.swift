import Foundation
import ImageIO
import UniformTypeIdentifiers

/// EXIF/GPS/dimensions extraction via ImageIO. Never downloads cloud placeholders.
enum ImageMetadata {
    static func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image)
    }

    static func extract(url: URL) -> ImageInfo? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return nil }

        var info = ImageInfo()
        info.pixelWidth = properties[kCGImagePropertyPixelWidth as String] as? Int
        info.pixelHeight = properties[kCGImagePropertyPixelHeight as String] as? Int
        if let typeID = CGImageSourceGetType(source) as String? {
            info.format = UTType(typeID)?.description ?? typeID
        }
        if let model = properties[kCGImagePropertyColorModel as String] as? String {
            info.colorModel = model
        }
        info.orientation = properties[kCGImagePropertyOrientation as String] as? Int

        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            info.cameraMake = (exif[kCGImagePropertyExifLensMake as String] as? String) ?? nil
            info.lensModel = (exif[kCGImagePropertyExifLensModel as String] as? String) ?? nil
            if let isoList = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int], let first = isoList.first {
                info.iso = first
            } else if let iso = exif[kCGImagePropertyExifISOSpeedRatings as String] as? Int {
                info.iso = iso
            }
            if let exposure = exif[kCGImagePropertyExifExposureTime as String] as? Double {
                info.exposure = formatExposure(exposure)
            }
            info.fNumber = exif[kCGImagePropertyExifFNumber as String] as? Double
            info.focalLength = exif[kCGImagePropertyExifFocalLength as String] as? Double
            if let raw = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                info.takenDate = parseEXIFDate(raw)
            }
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            info.cameraMake = info.cameraMake ?? (tiff[kCGImagePropertyTIFFMake as String] as? String)
            info.cameraModel = tiff[kCGImagePropertyTIFFModel as String] as? String
        }

        if let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            if let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double {
                let ref = gps[kCGImagePropertyGPSLatitudeRef as String] as? String ?? "N"
                info.latitude = ref.uppercased() == "S" ? -abs(lat) : abs(lat)
            }
            if let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double {
                let ref = gps[kCGImagePropertyGPSLongitudeRef as String] as? String ?? "E"
                info.longitude = ref.uppercased() == "W" ? -abs(lon) : abs(lon)
            }
        }
        return info
    }

    static func formatExposure(_ seconds: Double) -> String {
        guard seconds > 0 else { return Fmt.unknown }
        if seconds >= 1 {
            return String(format: "%.1fs", seconds)
        }
        return "1/\(Int((1.0 / seconds).rounded()))"
    }

    static func parseEXIFDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: raw)
    }
}
