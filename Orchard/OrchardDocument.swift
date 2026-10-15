//
//  OrchardDocument.swift
//  Orchard
//
//  Created by David Amouzou on 15/10/2026.
//

import SwiftUI
import UniformTypeIdentifiers

@Observable
final class OrchardDocument: Document {

    static let readableContentTypes: [UTType] = [.exampleText]

    var text: String

    init(text: String = "Hello, world!") {
        self.text = text
    }

    nonisolated func reader(
        configuration: sending ReadConfiguration
    ) -> sending FileWrapperDocumentReader<String> {
        FileWrapperDocumentReader(configuration) { fileWrapper in
            guard let data = fileWrapper.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return String(decoding: data, as: UTF8.self)
        }
    }

    nonisolated func writer(
        configuration: sending WriteConfiguration
    ) -> sending FileWrapperDocumentWriter<String> {
        FileWrapperDocumentWriter(configuration) { snapshot, _ in
            FileWrapper(regularFileWithContents: Data(snapshot.utf8))
        }
    }

    @MainActor
    func snapshot(contentType: UTType) async throws -> sending String {
        text
    }

    @MainActor
    func apply(snapshot: sending String, previous: sending String?) async throws {
        text = snapshot
    }
}

extension UTType {
    static var exampleText: UTType {
        UTType(importedAs: "com.example.plain-text")
    }
}
