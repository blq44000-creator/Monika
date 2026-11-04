import Foundation
import UIKit
import UniformTypeIdentifiers
import PDFKit

/// Nature d'une pièce jointe en attente d'envoi.
enum PendingAttachmentKind {
    case image(jpegData: Data, preview: UIImage)
    case document(extractedText: String)
}

/// Pièce jointe sélectionnée par l'utilisateur avant l'envoi du message.
struct PendingAttachment: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    let kind: PendingAttachmentKind

    var isImage: Bool {
        if case .image = kind { return true }
        return false
    }

    static func == (lhs: PendingAttachment, rhs: PendingAttachment) -> Bool {
        lhs.id == rhs.id
    }
}

/// Erreurs de lecture ou de préparation d'une pièce jointe.
enum AttachmentError: LocalizedError {
    case unreadableImage
    case unreadableDocument
    case emptyDocument

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "Impossible de lire cette image."
        case .unreadableDocument:
            return "Impossible de lire ce fichier."
        case .emptyDocument:
            return "Ce document ne contient aucun texte exploitable."
        }
    }
}

/// Traitement des photos et fichiers joints :
/// - Images redimensionnées à 1024 px maximum et compressées en JPEG (qualité 0.7).
/// - Fichiers PDF extraits via `PDFKit` et fichiers texte décodés proprement.
enum AttachmentProcessor {
    static let maxImageDimension: CGFloat = 1024
    static let jpegQuality: CGFloat = 0.7
    private static let maxExtractedCharacters = 60_000

    static func processImageData(_ data: Data, fileName: String = "Photo.jpg") throws -> PendingAttachment {
        guard let original = UIImage(data: data),
              let (jpegData, preview) = resizedJPEG(from: original)
        else {
            throw AttachmentError.unreadableImage
        }
        return PendingAttachment(fileName: fileName, kind: .image(jpegData: jpegData, preview: preview))
    }

    static func processImportedFile(at url: URL) throws -> PendingAttachment {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = url.lastPathComponent.isEmpty ? "Fichier" : url.lastPathComponent
        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)

        if let contentType, contentType.conforms(to: .image) {
            guard let data = try? Data(contentsOf: url) else {
                throw AttachmentError.unreadableImage
            }
            return try processImageData(data, fileName: fileName)
        }

        if contentType?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf" {
            return try processPDF(at: url, fileName: fileName)
        }

        guard let rawData = try? Data(contentsOf: url) else {
            throw AttachmentError.unreadableDocument
        }

        // Si le fichier est malgré tout une image sans extension reconnue
        if let image = UIImage(data: rawData),
           let (jpegData, preview) = resizedJPEG(from: image) {
            return PendingAttachment(fileName: fileName, kind: .image(jpegData: jpegData, preview: preview))
        }

        guard let decoded = decodeText(from: rawData) else {
            throw AttachmentError.unreadableDocument
        }

        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AttachmentError.emptyDocument
        }

        let capped = String(trimmed.prefix(maxExtractedCharacters))
        return PendingAttachment(fileName: fileName, kind: .document(extractedText: capped))
    }

    // MARK: - Helpers privés

    private static func processPDF(at url: URL, fileName: String) throws -> PendingAttachment {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw AttachmentError.unreadableDocument
        }

        var pages: [String] = []
        for index in 0..<document.pageCount {
            if let pageText = document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pageText.isEmpty {
                pages.append(pageText)
            }
        }

        let joined = pages.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !joined.isEmpty {
            let capped = String(joined.prefix(maxExtractedCharacters))
            return PendingAttachment(fileName: fileName, kind: .document(extractedText: capped))
        }

        // PDF scanné sans couche texte : conversion de la première page en image 1024 px
        if let firstPage = document.page(at: 0) {
            let thumbnail = firstPage.thumbnail(
                of: CGSize(width: maxImageDimension, height: maxImageDimension),
                for: .mediaBox
            )
            if let (jpegData, preview) = resizedJPEG(from: thumbnail) {
                return PendingAttachment(fileName: fileName, kind: .image(jpegData: jpegData, preview: preview))
            }
        }

        throw AttachmentError.emptyDocument
    }

    private static func decodeText(from data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let utf16 = String(data: data, encoding: .utf16) {
            return utf16
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        return nil
    }

    private static func resizedJPEG(from image: UIImage) -> (Data, UIImage)? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let longestSide = max(pixelWidth, pixelHeight)
        let targetSize: CGSize
        if longestSide > maxImageDimension {
            let scaleFactor = maxImageDimension / longestSide
            targetSize = CGSize(
                width: max(1, floor(pixelWidth * scaleFactor)),
                height: max(1, floor(pixelHeight * scaleFactor))
            )
        } else {
            targetSize = CGSize(
                width: max(1, floor(pixelWidth)),
                height: max(1, floor(pixelHeight))
            )
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let rendered = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpegData = rendered.jpegData(compressionQuality: jpegQuality) else {
            return nil
        }
        return (jpegData, rendered)
    }
}
