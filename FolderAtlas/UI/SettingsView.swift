import SwiftUI

/// Default scan settings and column reset.
struct SettingsView: View {
    @AppStorage("scan.includeHidden") private var includeHidden = true
    @AppStorage("scan.includePackages") private var includePackages = true
    @AppStorage("scan.computeFolderSizes") private var computeFolderSizes = true
    @AppStorage("sort.foldersFirst") private var foldersFirst = true

    var body: some View {
        Form {
            Section {
                Toggle("Include hidden files", isOn: $includeHidden)
                Toggle("Include package contents (.app, .bundle…)", isOn: $includePackages)
                Toggle("Compute folder sizes and counts during scans", isOn: $computeFolderSizes)
                Toggle("Folders on top (sorting)", isOn: $foldersFirst)
            } header: {
                Text("Scanning")
            } footer: {
                Text("Symlinks are never followed during recursion, so cycles are impossible. iCloud placeholders are recorded but never downloaded.")
            }
            Section {
                Button("Reset Column Layout") { NodeColumn.reset() }
            } header: {
                Text("View")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 300)
    }
}
