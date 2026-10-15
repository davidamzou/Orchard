//
//  OrchardApp.swift
//  Orchard
//
//  Created by David Amouzou on 15/10/2026.
//

import SwiftUI

@main
struct OrchardApp: App {
    var body: some Scene {
        DocumentGroup { document in
            ContentView(document: document)
        } makeDocument: { configuration, context in
            OrchardDocument()
        }
    }
}
