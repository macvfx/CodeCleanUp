import SwiftUI

struct RunLogView: View {
    @ObservedObject var runManager: RunManager

    var body: some View {
        ScrollView {
            Text(runManager.logText.isEmpty ? "No runs yet." : runManager.logText)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
        }
        .frame(minWidth: 560, minHeight: 360)
        .navigationTitle("Run Log")
    }
}
