import SwiftUI
import UIKit

/// Image data cropped to fill whatever frame it is given.
struct PhotoImage: View {
    let data: Data?
    var cornerRadius: CGFloat = 0

    var body: some View {
        Color.clear
            .overlay {
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(.fill.tertiary)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
    }
}
