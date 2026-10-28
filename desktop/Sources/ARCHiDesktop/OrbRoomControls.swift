import SwiftUI
import AppKit

/// Another surface of the existing native/Unity session, not an independent app or profile.
@MainActor
struct OrbRoomControls: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject private var connection: UnityPresentationConnection
    @ObservedObject private var speech: OrbSpeechPlayback
    @State private var command = ""
    @State private var commandNotice = ""

    init(store: CompanionStore) {
        self.store = store
        connection = store.unityPresentation
        speech = store.unityPresentation.orbSpeech
    }

    private var supported: Bool {
        guard store.activeQiMon?.isValid == true, let player = connection.availablePlayer else { return false }
        return UnityPresentationConnection.supportsOrb(player)
            && store.unityPresentationUnavailableReason(for: player) == nil
    }
    private var opened: Bool { connection.isSharing && connection.orbPresentation != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("ARCHi Orb", systemImage: "circle.hexagongrid.fill")
                .font(.system(size: 20, weight: .medium))
            Text("Your existing ARCHi, present in a room. Its rings follow real assistant activity, dictation and speech playback.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(opened ? "Return to orb" : "Open orb room") {
                    if !store.isVisible { store.showCompanion() }
                    Task { await connection.open(store: store, destination: .companion,
                        orb: connection.orbPresentation ?? UnityOrbPresentation()) }
                }
                .buttonStyle(WorkspaceActionStyle(prominent: true))
                .disabled(!supported || store.isShuttingDown)
                .accessibilityIdentifier("orb.open")
                Button("Ask ARCHi") { store.open(.assistant) }.buttonStyle(.borderless)
                Button("Memory map") { store.open(.memory) }.buttonStyle(.borderless)
            }
            if !supported {
                Text(store.activeQiMon == nil ? "Choose your existing companion first."
                    : "Orb rendering needs the updated Unity helper. The selected helper has not advertised support yet.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            DisclosureGroup("Headset setup") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect a separate tracked renderer to this same ARCHi session. The headset setup guide covers room mapping and private pairing.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Prepare headset session") {
                        if !store.isVisible { store.showCompanion() }
                        connection.prepareOrbHeadset(store: store)
                    }.disabled(connection.isSharing || store.activeQiMon?.isValid != true || store.isShuttingDown)
                    if let path = connection.orbTransportSourceURL {
                        Button("Copy session file path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(path.path, forType: .string)
                        }.buttonStyle(.borderless)
                    }
                }.padding(.top, 8)
            }.font(.system(size: 11))
            if let orb = connection.orbPresentation, opened {
                HStack(spacing: 16) {
                    Picker("Room", selection: Binding(get: { connection.orbPresentation?.theme ?? .room },
                        set: { connection.applyOrbCommand(.theme($0), store: store) })) {
                        ForEach(UnityOrbPresentation.Theme.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Orb position", selection: Binding(get: { connection.orbPresentation?.anchor ?? .world },
                        set: { connection.applyOrbCommand(.anchor($0), store: store) })) {
                        ForEach(UnityOrbPresentation.Anchor.allCases) { Text($0.title).tag($0) }
                    }
                }.font(.system(size: 11))
                HStack {
                    TextField("Try: make this room voxel", text: $command)
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("orb.command")
                        .onSubmit { runCommand() }
                    Button("Apply") { runCommand() }.disabled(command.isEmpty)
                }
                if !commandNotice.isEmpty { Text(commandNotice).font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button(speech.isSpeaking ? "Stop speaking" : "Speak current reply") {
                        if speech.isSpeaking { speech.stop() }
                        else { speech.speak(store.reply) }
                    }
                    .disabled(store.isWorking || store.preferences.quiet || !store.isVisible || store.isShuttingDown)
                    .accessibilityIdentifier("orb.speech")
                    Toggle("Read completed replies", isOn: $connection.readOrbReplies)
                        .font(.system(size: 11)).toggleStyle(.checkbox)
                }
                Text("\(orb.theme.title) · \(connection.hasRenderAcknowledgment ? "renderer acknowledged" : "waiting for renderer")")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Text("Use Dictate in Ask ARCHi for speech input. Review and Send use your existing controls. Room choices last for this session; QiMon keeps its own game saves.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(WorkspaceSurface())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("orb.controls")
    }

    private func runCommand() {
        if connection.handleOrbCommand(command, store: store) { command = ""; commandNotice = "Requested through ARCHi." }
        else { commandNotice = "Try a room theme, ‘show memories’, ‘open QiMon’ or ‘follow me’. Use Ask ARCHi for other questions." }
    }
}
