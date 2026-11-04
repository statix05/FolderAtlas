import SwiftUI

/// Combinable filters: kind, extension, size, dates, tags, hidden state,
/// symlinks, errors, cloud state and source availability.
struct FilterPopover: View {
    @Bindable var session: MapSession
    @Environment(\.dismiss) private var dismiss

    @State private var minSizeText = ""
    @State private var maxSizeText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                kindsRow
                extensionsRow
                sizeRow
                datesRow
                tagsRow
                flagsRow
                HStack {
                    Button("Reset Filters") {
                        session.filter = FilterCriteria()
                        minSizeText = ""
                        maxSizeText = ""
                    }
                    Spacer()
                    Button("Close") { dismiss() }
                }
            }
            .padding()
        }
        .onAppear {
            if let minSize = session.filter.minSize {
                minSizeText = String(Int(max(0, Double(minSize) / 1_048_576.0)))
            }
            if let maxSize = session.filter.maxSize {
                maxSizeText = String(Int(max(0, Double(maxSize) / 1_048_576.0)))
            }
        }
    }

    private var kindsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Types").font(.caption).foregroundStyle(.secondary)
            HStack {
                ForEach(FilterCriteria.KindOption.allCases) { option in
                    Toggle(kindLabel(option), isOn: Binding(
                        get: { session.filter.kinds.contains(option) },
                        set: { on in
                            if on { session.filter.kinds.insert(option) }
                            else { session.filter.kinds.remove(option) }
                        }))
                }
            }
            Divider()
            Toggle("Folders on top", isOn: Binding(
                get: { session.foldersFirst },
                set: { session.foldersFirst = $0 }))
        }
    }

    private func kindLabel(_ option: FilterCriteria.KindOption) -> String {
        switch option {
        case .files: return String(localized: "Files")
        case .folders: return String(localized: "Folders")
        case .packages: return String(localized: "Packages")
        case .symlinks: return String(localized: "Symlinks")
        }
    }

    @ViewBuilder
    private var extensionsRow: some View {
        let extensions = session.snapshot?.topExtensions ?? []
        if !extensions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Extensions").font(.caption).foregroundStyle(.secondary)
                FlexChips(items: extensions, selected: Binding(
                    get: { session.filter.extensions },
                    set: { session.filter.extensions = $0 }))
            }
        }
    }

    private var sizeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Size (MB)").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("min", text: $minSizeText)
                    .frame(width: 90)
                    .onChange(of: minSizeText) { _, value in
                        session.filter.minSize = parseMB(value)
                    }
                Text("–")
                TextField("max", text: $maxSizeText)
                    .frame(width: 90)
                    .onChange(of: maxSizeText) { _, value in
                        session.filter.maxSize = parseMB(value)
                    }
            }
        }
    }

    private var datesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dates").font(.caption).foregroundStyle(.secondary)
            optionalDate("Created from", Binding(
                get: { session.filter.createdFrom },
                set: { session.filter.createdFrom = $0 }))
            optionalDate("Created to", Binding(
                get: { session.filter.createdTo },
                set: { session.filter.createdTo = $0 }))
            optionalDate("Modified from", Binding(
                get: { session.filter.modifiedFrom },
                set: { session.filter.modifiedFrom = $0 }))
            optionalDate("Modified to", Binding(
                get: { session.filter.modifiedTo },
                set: { session.filter.modifiedTo = $0 }))
        }
    }

    private func optionalDate(_ title: String, _ binding: Binding<Date?>) -> some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { binding.wrappedValue != nil },
                set: { on in binding.wrappedValue = on ? Date() : nil }))
            if binding.wrappedValue != nil {
                DatePicker("", selection: Binding(
                    get: { binding.wrappedValue ?? Date() },
                    set: { binding.wrappedValue = $0 }))
                    .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private var tagsRow: some View {
        let tags = session.snapshot?.allTags ?? []
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tags").font(.caption).foregroundStyle(.secondary)
                FlexChips(items: tags, selected: Binding(
                    get: { session.filter.tags },
                    set: { session.filter.tags = $0 }))
            }
        }
    }

    private var flagsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("States").font(.caption).foregroundStyle(.secondary)
            Picker("Hidden files", selection: $session.filter.hiddenMode) {
                Text("Any").tag(FilterCriteria.HiddenMode.any)
                Text("Only hidden").tag(FilterCriteria.HiddenMode.onlyHidden)
                Text("No hidden").tag(FilterCriteria.HiddenMode.noHidden)
            }
            Picker("Source availability", selection: $session.filter.availability) {
                Text("Any").tag(FilterCriteria.Availability.any)
                Text("Available").tag(FilterCriteria.Availability.available)
                Text("Unavailable").tag(FilterCriteria.Availability.unavailable)
            }
            Toggle("Symlinks only", isOn: $session.filter.onlySymlinks)
            Toggle("With scan errors", isOn: $session.filter.onlyWithError)
            Toggle("Not downloaded from iCloud", isOn: $session.filter.onlyNotDownloaded)
        }
    }

    private func parseMB(_ text: String) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Double(trimmed.replacing(",", with: ".")), value >= 0 else {
            return nil
        }
        return Int64(value * 1_048_576.0)
    }
}

/// Simple wrapping chip row for extension/tag filters.
struct FlexChips: View {
    let items: [String]
    @Binding var selected: Set<String>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Toggle(item, isOn: Binding(
                    get: { selected.contains(item) },
                    set: { on in
                        if on { selected.insert(item) } else { selected.remove(item) }
                    }))
                    .toggleStyle(.button)
                    .controlSize(.small)
            }
        }
    }
}
