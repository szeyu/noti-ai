import SwiftUI

/// The full answer: your highlighted text on a marker stroke, then the reply set like a page.
struct AnswerView: View {
    let question: String
    let answer: String
    let source: String
    var onClose: () -> Void = {}
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(question.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.ink) // fixed ink: stays readable on yellow in dark mode
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true) // wrap instead of truncating to one line
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(MarkerShape().fill(Theme.marker))
                .padding(.trailing, 24)

            ScrollView {
                Text(answer)
                    .font(.system(size: 16, design: .serif))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline) {
                Text(source)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Copied" : "Copy answer") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(answer, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onClose() }
                }
                .buttonStyle(MarkerButtonStyle())
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .frame(width: 440)
    }
}
