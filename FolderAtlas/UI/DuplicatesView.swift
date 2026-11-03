import SwiftUI

/// Duplicate content groups: size bucketing + SHA-256 confirmation.
/// v1 shows and compares duplicates; deletion is out of scope.
struct DuplicatesView: View {
    @Bindable var session: MapSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let report = session.duplicatesReport {
                if report.groups.isEmpty {
                    ContentUnavailableView("No duplicates", systemImage: "checkmark.seal",
                                           description: Text("No files with identical content were found."))
                } else {
                    Text("\(report.groups.count) groups · \(report.candidateCount) candidates hashed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(report.groups) { group in
                                Group {
                                    DisclosureGroup {
                                        ForEach(group.nodes) { node in
                                            duplicateRow(node)
                                        }
                                    } label: {
                                        HStack {
                                            Text("\(group.nodes.count) ×")
                                                .bold()
                                            Text(Fmt.size(group.size))
                                            Text(group.hash.prefix(12))
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.tertiary)
                                            Spacer()
                                            Text("wasted: \(Fmt.size(group.size * Int64(group.nodes.count - 1)))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                Text("FolderAtlas only reports duplicates. Removing them is intentionally not part of version 1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Computing content hashes…")
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 640, height: 480)
    }

    private func duplicateRow(_ node: NodeRecord) -> some View {
        HStack {
            Image(systemName: NodeIcons.symbol(for: node))
                .foregroundStyle(.secondary)
            Text(node.relativePath)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(Fmt.date(node.modified))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Reveal") { session.reveal(node) }
            Button("Copy Path") { session.copyPath(node) }
        }
        .font(.callout)
    }
}
