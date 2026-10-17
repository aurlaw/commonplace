import LinkPresentation
import SwiftUI
import UIKit

/// An entry's body with its Markdown rendered: paragraphs, bulleted lists with a hanging
/// indent, bold, italic, and tappable links. A plain entry renders exactly as plain text did.
struct FormattedBody: View {
    /// The stored Markdown.
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownBody.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(MarkdownBody.inline(text))
                case .bulletList(let items):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•")
                                    .accessibilityHidden(true)
                                Text(MarkdownBody.inline(item))
                            }
                        }
                    }
                }
            }
        }
        .lineSpacing(3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Rich previews for an entry's first few http(s) links, in reading order. Each fetches when
/// it comes on screen; until its metadata is there (or offline), it is a compact row.
struct LinkPreviews: View {
    let urls: [URL]

    init(body: String) {
        urls = Array(MarkdownBody.links(in: body).prefix(LinkPreviewRule.maximumPerEntry))
    }

    var body: some View {
        if !urls.isEmpty {
            VStack(spacing: 10) {
                ForEach(urls, id: \.self) { url in
                    LinkPreview(url: url)
                }
            }
        }
    }
}

private struct LinkPreview: View {
    let url: URL

    @Environment(\.linkMetadataService) private var service
    @Environment(\.openURL) private var openURL
    @State private var metadata: LPLinkMetadata?

    var body: some View {
        Group {
            if let metadata {
                LinkCard(metadata: metadata)
            } else {
                compactRow
            }
        }
        .task(id: url) {
            metadata = await service.metadata(for: url)
        }
    }

    /// Loading, offline, or failed: the link itself, never an empty card.
    private var compactRow: some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.host() ?? url.absoluteString)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(url.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Link, \(url.host() ?? url.absoluteString)")
    }
}

/// `LPLinkView` sized to the content column. It opens the link itself when tapped.
private struct LinkCard: UIViewRepresentable {
    let metadata: LPLinkMetadata

    func makeUIView(context: Context) -> LPLinkView {
        let view = LPLinkView(metadata: metadata)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: LPLinkView, context: Context) {
        if view.metadata !== metadata {
            view.metadata = metadata
            view.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: LPLinkView, context: Context) -> CGSize?
    {
        let width = proposal.width ?? 320
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}

#Preview("Formatted") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            FormattedBody(FormattedBodyPreview.sample)
            LinkPreviews(body: FormattedBodyPreview.sample)
        }
        .padding(20)
    }
    .sampleData()
}

#Preview("Formatted · Dark") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            FormattedBody(FormattedBodyPreview.sample)
            LinkPreviews(body: FormattedBodyPreview.sample)
        }
        .padding(20)
    }
    .sampleData()
    .preferredColorScheme(.dark)
}

#Preview("Previews loading") {
    LinkPreviews(body: FormattedBodyPreview.sample)
        .padding(20)
        .sampleData(links: FakeLinkMetadataService(delay: .seconds(600)))
}

private enum FormattedBodyPreview {
    static let sample = """
        Dinner at [Elote Cafe](https://elotecafe.com). **Get the fire-roasted corn**, and \
        *don't* skip the dessert.

        - 50-minute wait
        - Worth it
        - Trail notes: https://www.fs.usda.gov/recarea/coconino/recarea/?recid=55291

        Literal `code` and ~strike~ stay as typed.
        """
}
