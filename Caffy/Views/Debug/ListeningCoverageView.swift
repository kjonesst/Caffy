#if DEBUG
import SwiftData
import SwiftUI

/// DEBUG only: the listening coverage report for the real photo and music
/// libraries, as text to read and share off the phone.
struct ListeningCoverageView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var report: ListeningCoverage?

    var body: some View {
        NavigationStack {
            Group {
                if let report {
                    ScrollView {
                        Text(report.text)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                } else {
                    ProgressView("Reading your libraries…")
                }
            }
            .navigationTitle("Listening coverage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if let report {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: report.text)
                    }
                }
            }
        }
        .task {
            report = await ListeningCoverage.run(container: modelContext.container)
        }
    }
}
#endif
