import SwiftUI

/// Shared row used by ConsolidateTagsSheet and ConsolidateAuthorsSheet.
/// Renders `from₁ from₂ → into` with a strikethrough on the `from` entries
/// and an optional rationale below. A `prefix` (e.g. "#") is applied to each
/// rendered value when the vocabulary uses one — tags do, authors don't.
///
/// Extracted because the two sheets had drifted to slightly different row
/// layouts already (the tags row had vertical padding, the authors row
/// didn't) and the next polish pass would have diverged them further.
struct MergeProposalRow: View {
    var from: [String]
    var into: String
    var reason: String
    var approved: Binding<Bool>
    /// Applied to every from/into label. "#" for tags, empty for authors.
    var prefix: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: approved)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    ForEach(from, id: \.self) { value in
                        Text("\(prefix)\(value)")
                            .strikethrough()
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(prefix)\(into)")
                        .foregroundStyle(.primary)
                        .fontWeight(.medium)
                        .font(.callout)
                }
                if !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
