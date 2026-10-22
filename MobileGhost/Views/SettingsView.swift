// Mobile Ghost additions, 2026-10-22. AGPL-3.0.
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserDefaults.Keys.targetDeviceIP) private var targetIP = DeviceConnectionContext.defaultTargetIPAddress
    @ObservedObject private var tunnel = TunnelManager.shared
    @ObservedObject private var mounting = MountingProgress.shared
    @ObservedObject private var background = BackgroundLocationManager.shared
    @State private var importing = false
    @State private var message: String?
    @State private var downloading = false
    var body: some View {
        NavigationStack {
            Form {
                Section("iPhone setup") {
                    Text("Enable Developer Mode, import this iPhone’s pairing file, and connect LocalDevVPN while joined to Wi-Fi.")
                    Link("Pairing-file guide",destination:URL(string:"https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md")!)
                    Link("Get LocalDevVPN",destination:URL(string:"https://apps.apple.com/us/app/localdevvpn/id6755608044")!)
                    Button("Import pairing file") { importing = true }
                    TextField("Device address",text:$targetIP).keyboardType(.decimalPad).autocorrectionDisabled()
                    Button("Retry connection") { startTunnelAfterPendingLocationCommands(); MountingProgress.shared.checkforMounted() }
                    LabeledContent("Tunnel",value:tunnel.isConnected ? "Connected" : "Not connected")
                    LabeledContent("Developer image",value:mounting.coolisMounted ? "Mounted" : "Not mounted")
                    Button(downloading ? "Preparing…" : "Prepare developer image") {
                        downloading = true
                        Task {
                            do { try await DeveloperDiskImageService.shared.downloadMissingFiles(); MountingProgress.shared.pubMount(); message = "Download complete; mounting requested." }
                            catch { message = error.localizedDescription }
                            downloading = false
                        }
                    }.disabled(downloading)
                    if let message { Text(message).font(.caption) }
                }
                Section("During a journey") {
                    LabeledContent("Location permission", value: background.permissionDescription)
                    Button("Allow background location") { background.requestAlwaysPermission() }
                    Button("Open iPhone Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                    Text("Active routes and fixed positions continue refreshing when you switch apps or lock the screen, while iOS permits background location execution. Allow location access and keep LocalDevVPN connected. A location indicator may appear and battery use increases.")
                    Text("Force-quitting, iOS suspension, or losing the VPN can interrupt updates. After an execution gap, movement pauses instead of jumping ahead. A fixed position may persist or revert; verify it on your phone. Pending departures still require the app in the foreground.")
                    Text("A successful command is not proof of what another app displays. Check Maps after setting and restoring a location.")
                }
                Section("Privacy and credits") {
                    Text("Places and the last session point are stored on this iPhone. Apple Maps receives search and route requests. Bus-stop searches send the map centre to OpenStreetMap’s Overpass service. Developer images download from the upstream GitHub source. No analytics or app account.")
                    Link("OpenStreetMap contributors · ODbL",destination:URL(string:"https://www.openstreetmap.org/copyright")!)
                    Text("Based on TLocation and StikDebug by Stephen Bove and contributors; device library by Jackson Coxson. Independent Mobile Ghost modifications dated October 22, 2026. AGPL-3.0, no warranty.")
                    Link("Source, license and setup",destination:URL(string:"https://github.com/rehanjafar/mobile-ghost")!)
                }.font(.footnote)
            }.navigationTitle("Connection").toolbar { Button("Done") { dismiss() } }
            .fileImporter(isPresented:$importing,allowedContentTypes:PairingFileStore.supportedContentTypes) { result in
                do { try PairingFileStore.importFromPicker(result.get()); markTunnelDisconnected(); startTunnelAfterPendingLocationCommands(); message = "Pairing file imported." }
                catch { message = error.localizedDescription }
            }
        }
    }
}
