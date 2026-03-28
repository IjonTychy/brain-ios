import SwiftUI
import BrainCore
import AVKit
import WebKit
import CoreImage.CIFilterBuiltins

// System render functions for SkillRenderer.
// Split from SkillRenderer.swift to speed up Swift compilation.
// All functions return AnyView for type erasure to avoid compile timeouts.

extension SkillRenderer {

    func renderOpenUrl(_ node: ScreenNode) -> AnyView {
        let title = resolveString(node, "title") ?? "Öffnen"
        let urlStr = resolveString(node, "url") ?? ""
        if let url = URL(string: urlStr), urlStr.hasPrefix("https://") {
            return AnyView(
                Link(title, destination: url)
                    .accessibilityLabel(title)
            )
        } else {
            return AnyView(
                Text(title).foregroundStyle(.secondary)
            )
        }
    }

    func renderCopyButton(_ node: ScreenNode) -> AnyView {
        let text = resolveString(node, "text") ?? ""
        let label = resolveString(node, "label") ?? "Kopieren"
        return AnyView(
            Button {
                UIPasteboard.general.string = text
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label(label, systemImage: "doc.on.doc")
            }
            .accessibilityLabel(label)
        )
    }

    func renderQRCode(_ node: ScreenNode) -> AnyView {
        let data = resolveString(node, "data") ?? ""
        let size = resolveDouble(node, "size") ?? 200

        if let qrImage = generateQRCode(from: data) {
            return AnyView(
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: CGFloat(size), height: CGFloat(size))
                    .accessibilityLabel("QR-Code: \(data)")
            )
        } else {
            return AnyView(
                Image(systemName: "qrcode")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
            )
        }
    }

    func renderVideoPlayer(_ node: ScreenNode) -> AnyView {
        let urlStr = resolveString(node, "url") ?? ""
        let height = resolveDouble(node, "height") ?? 250

        if let url = URL(string: urlStr), urlStr.hasPrefix("https://") {
            return AnyView(
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: CGFloat(height))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            )
        } else {
            return renderSpecialPlaceholder("Video Player", icon: "play.rectangle")
        }
    }

    func renderAudioPlayer(_ node: ScreenNode) -> AnyView {
        let title = resolveString(node, "title") ?? "Audio"
        return AnyView(
            HStack {
                Button { /* playback controlled by actions */ } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                }
                Text(title).font(.callout)
                Spacer()
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("Audio: \(title)")
        )
    }

    func renderWebView(_ node: ScreenNode) -> AnyView {
        let urlStr = resolveString(node, "url") ?? ""
        let height = resolveDouble(node, "height") ?? 400

        if let url = URL(string: urlStr), urlStr.hasPrefix("https://") {
            return AnyView(
                WebViewWrapper(url: url)
                    .frame(height: CGFloat(height))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            )
        } else {
            return renderSpecialPlaceholder("WebView", icon: "globe")
        }
    }

    // MARK: - QR Code generation

    func generateQRCode(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaled = ciImage.transformed(by: transform)
        return UIImage(ciImage: scaled)
    }
}
