import SwiftUI
import AppKit
import ImageIO

/// Inspector: metadata of the selected node (or map summary), preview and actions.
struct InspectorView: View {
    @Bindable var session: MapSession

    var body: some View {
        Group {
            if session.selection.count > 1 {
                multipleSummary
            } else if let node = session.singleSelectedNode {
                nodeDetails(node)
            } else if let snapshot = session.snapshot {
                mapSummary(snapshot)
            } else {
                ContentUnavailableView("Nothing selected", systemImage: "cursorarrow.rays",
                                       description: Text("Select an item in the map to inspect its metadata."))
            }
        }
        .padding()
    }

    // MARK: - Single node

    @ViewBuilder
    private func nodeDetails(_ node: NodeRecord) -> some View {
        let url = session.absoluteURL(of: node)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PreviewThumb(url: url, node: node)
                Text(node.displayName)
                    .font(.title3)
                    .bold(node.isDirectory)
                actionRow(node, url: url)
                if let error = node.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                metadataRows(node, url: url)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actionRow(_ node: NodeRecord, url: URL) -> some View {
        HStack(spacing: 8) {
            Button("Open") { session.open(node) }
            Button("Reveal") { session.reveal(node) }
            Button {
                session.quickLookSelection()
            } label: {
                Text("Quick Look")
            }
            Menu {
                Button("Copy Path") { session.copyPath(node) }
                Button("Copy Name") { NSPasteboardHelper.copy(node.name) }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .menuStyle(.borderlessButton)
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func metadataRows(_ node: NodeRecord, url: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Kind", NodeFormatters.kindName(node.kind))
            row("Extension", node.ext ?? Fmt.unknown)
            row("Path (absolute)", url.path, selectable: true)
            row("Path (relative)", node.relativePath.isEmpty ? "/" : node.relativePath, selectable: true)
            row("Size", Fmt.size(node.size))
            row("Size on disk", Fmt.size(node.allocSize))
            row("Created", Fmt.date(node.created))
            row("Modified", Fmt.date(node.modified))
            row("Tags", node.tags?.joined(separator: ", ") ?? Fmt.unknown)
            if node.isDirectory {
                row("Items", Fmt.count(node.childCount))
                row("Nested items", Fmt.count(node.descendantCount))
                row("Folder size", Fmt.size(node.dirSize))
            }
            if node.isSymlink {
                row("Symlink", "Yes")
            }
            if node.notDownloaded {
                Label("Cloud placeholder — the file is not downloaded. FolderAtlas never triggers downloads.",
                      systemImage: "icloud.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let sha = node.sha256 {
                row("SHA-256", sha, monospaced: true, selectable: true)
            } else {
                Button("Compute SHA-256") {
                    session.selection = [node.id]
                    session.computeChecksums(scope: .selection)
                }
                .controlSize(.small)
            }
            if let image = node.imageInfo {
                Divider()
                row("Dimensions", Fmt.dimensions(image.pixelWidth, image.pixelHeight))
                row("Image format", image.format ?? Fmt.unknown)
                row("Color model", image.colorModel ?? Fmt.unknown)
                let cameraParts: [String?] = [image.cameraMake, image.cameraModel]
                let cameraName = cameraParts.compactMap { $0 }.joined(separator: " ")
                row("Camera", cameraName.isEmpty ? Fmt.unknown : cameraName)
                row("Lens", image.lensModel ?? Fmt.unknown)
                row("ISO", image.iso.map(String.init) ?? Fmt.unknown)
                row("Exposure", image.exposure ?? Fmt.unknown)
                row("Aperture", image.fNumber.map { String(format: "ƒ/%.1f", $0) } ?? Fmt.unknown)
                row("Focal length", image.focalLength.map { String(format: "%.0f mm", $0) } ?? Fmt.unknown)
                row("Date taken", Fmt.date(image.takenDate))
                if image.latitude != nil || image.longitude != nil {
                    row("GPS", Fmt.coordinates(image.latitude, image.longitude))
                }
            }
            if let media = node.mediaInfo {
                Divider()
                row(media.isVideo ? "Video duration" : "Audio duration", Fmt.seconds(media.durationSeconds))
                if media.isVideo {
                    row("Resolution", Fmt.dimensions(media.pixelWidth, media.pixelHeight))
                }
                row("Codec", media.codec ?? Fmt.unknown)
                row("Bitrate", media.bitrate.map { Fmt.size($0) + "/s" } ?? Fmt.unknown)
                if !media.isVideo {
                    row("Sample rate", media.sampleRate.map { String(format: "%.0f Hz", $0) } ?? Fmt.unknown)
                    row("Channels", media.channels.map(String.init) ?? Fmt.unknown)
                }
            }
        }
    }

    // MARK: - Multiple selection

    private var multipleSummary: some View {
        let nodes = session.selectedNodes
        let files = nodes.filter { !$0.isDirectory }
        let size = files.compactMap(\.size).reduce(0, +)
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(nodes.count) items selected")
                .font(.title3)
            Text("\(files.count) files · \(Fmt.size(size)) total")
                .foregroundStyle(.secondary)
            Divider()
            Button("Copy Paths") { session.copyPaths(nodes) }
            Button("Compute SHA-256") { session.computeChecksums(scope: .selection) }
            Button("Extract media & EXIF") { session.extractMediaMetadata(scope: .selection) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Map summary

    private func mapSummary(_ snapshot: Snapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.header.displayName).font(.title3)
                row("Source", snapshot.header.sourcePath, selectable: true)
                row("Scanned", Fmt.date(snapshot.header.createdAt))
                row("Files", String(snapshot.header.fileCount))
                row("Folders", String(snapshot.header.folderCount))
                row("Total size", Fmt.size(snapshot.header.totalSize))
                row("Scan duration", Fmt.seconds(snapshot.header.durationSeconds))
                row("Errors", String(snapshot.header.errorCount))
                row("Scan settings", snapshot.header.scanSettings.summary)
                if let available = session.sourceAvailable {
                    row("Source available", available ? String(localized: "Yes") : String(localized: "No"))
                }
                Divider()
                Text("The map is a snapshot of metadata, not a backup of file contents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ title: String, _ value: String, monospaced: Bool = false, selectable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .system(size: 11, design: .monospaced) : .body)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}

extension Notification.Name {
    static let faOpenExportSelection = Notification.Name("faOpenExportSelection")
}

/// Local image preview for images that are physically present.
struct PreviewThumb: View {
    let url: URL
    let node: NodeRecord

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .clipShape(.rect(cornerRadius: 6))
            } else {
                Image(systemName: NodeIcons.symbol(for: node))
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                    .frame(height: 80)
            }
        }
        .task(id: node.id) {
            image = nil
            guard !node.notDownloaded, !node.isDirectory,
                  ImageMetadata.isImageFile(url),
                  FileManager.default.fileExists(atPath: url.path) else { return }
            let target = url
            let result = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                let options = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 320
                ] as CFDictionary
                guard let source = CGImageSourceCreateWithURL(target as CFURL, nil),
                      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
                return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
            }.value
            image = result
        }
    }
}
