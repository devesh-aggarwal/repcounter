import SwiftUI
import UIKit

/// UIKit bridge: hands a rendered share card UIImage to UIActivityViewController
/// so the user can drop it into Messages, Mail, Files, Instagram, etc.
struct StatsShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
