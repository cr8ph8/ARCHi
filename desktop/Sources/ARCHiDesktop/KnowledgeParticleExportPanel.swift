import AppKit
import UniformTypeIdentifiers

/// A frozen, explicit local export attached to the actual workspace window.
/// The save panel stays alive independently of the graph's periodic refresh.
@MainActor
enum KnowledgeParticleExportPanel {
    static func save(_ data: Data, completion: @escaping (String) -> Void) {
        guard let window = (NSApp.keyWindow as? WorkspaceWindow)
                ?? NSApp.windows.compactMap({ $0 as? WorkspaceWindow }).first(where: \.isVisible),
              window.attachedSheet == nil else {
            completion("Open the ARCHi workspace and finish its current dialog before exporting.")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ARCHi-particle-map.json"
        panel.message = "Save record IDs, types, positions and links for Houdini. Source text and titles are excluded."
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                try data.write(to: url, options: .atomic)
                completion("Particle map exported. Source text and titles were excluded.")
            } catch {
                completion("Export did not finish. Your graph is unchanged.")
            }
        }
    }
}
