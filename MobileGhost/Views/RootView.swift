//
//  RootView.swift
//  MobileGhost
//

import SwiftUI
import Combine
import UIKit

private enum RootViewLinks {
    static let localDevVPNAppStore = URL(string: "https://apps.apple.com/us/app/localdevvpn/id6755608044")!

    /// Tried in order. SideStore renamed itself out of the AltStore lineage but both
    /// schemes are still in the wild, so guess the current one first and let the
    /// website catch anyone running neither.
    static let sideStore: [URL] = [
        URL(string: "sidestore://")!,
        URL(string: "altstore://")!,
        URL(string: "https://sidestore.io")!
    ]

    static let localDevVPN: [URL] = [
        URL(string: "stosvpn://")!,
        localDevVPNAppStore
    ]
}

/// Opens the first URL in `candidates` that the system actually resolves, chaining
/// through `open`'s completion handler.
///
/// Deliberately declaration-free: no `LSApplicationQueriesSchemes` entry and no
/// `canOpenURL` check. A scheme that does not resolve — app missing, or renamed
/// since LocalDevVPN was StosVPN — just reports failure and hands off to the next
/// candidate, so a wrong guess costs nothing but is invisible to the user.
///
/// A free function rather than a method so the recursive step does not have to
/// capture the enclosing `View` value in an escaping closure.
private func openFirstResolving(_ candidates: [URL]) {
    guard let next = candidates.first else { return }
    UIApplication.shared.open(next) { success in
        guard !success else { return }
        openFirstResolving(Array(candidates.dropFirst()))
    }
}

struct RootView: View {
    @ObservedObject private var tunnel = TunnelManager.shared
    @ObservedObject private var mounting = MountingProgress.shared
    @ObservedObject private var signing = SigningExpiryMonitor.shared

    @Environment(\.scenePhase) private var scenePhase

    @State private var isShowingPairingFilePicker = false
    @State private var isShowingSettings = false
    @State private var pairingExists = FileManager.default.fileExists(
        atPath: PairingFileStore.prepareURL().path
    )
    @State private var isShowingExpiryWarning = false
    @State private var suppressExpiryWarning = false
    /// The expiry warning is decided once per launch — but only once there is
    /// something to decide *with*. Without this, dismissing with "Later" would
    /// only last until the app next came back to the foreground.
    @State private var hasEvaluatedExpiryWarning = false

    private let statusTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isReady: Bool {
        pairingExists && tunnel.isConnected && mounting.coolisMounted
    }

    var body: some View {
        NavigationStack {
            // Until pairing + tunnel + DDI are all up, every control on the map is
            // disabled anyway. Rather than leave a normal-looking but silently dead
            // map, cover it with a blocking readiness overlay that says exactly what
            // is missing. The overlay is the last child of the ZStack (drawn on top)
            // and the map explicitly stops hit-testing beneath it, so nothing can be
            // tapped through — no accidental pin drops. A safe-area inset banner was
            // used here before and did not render on device, because the map below
            // discards the safe area.
            ZStack {
                GhostHomeView()
                    .allowsHitTesting(isReady && !isShowingExpiryWarning)

                // Strictly one card at a time — `else if`, not two independent
                // `if`s, so the two can never stack on top of each other. The
                // expiry warning wins: an unreadable map is recoverable in
                // seconds, a lapsed signature means a reinstall. Dismissing it
                // reveals the readiness overlay underneath, whose blocking
                // behaviour is unchanged (the map stops hit-testing for either).
                if isShowingExpiryWarning {
                    expiryOverlay
                } else if !isReady {
                    readinessOverlay
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isReady)
            .animation(.easeInOut(duration: 0.2), value: isShowingExpiryWarning)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .fileImporter(
            isPresented: $isShowingPairingFilePicker,
            allowedContentTypes: PairingFileStore.supportedContentTypes
        ) { result in
            importPairingFile(result)
        }
        .onAppear {
            startTunnelInBackground()
            MountingProgress.shared.checkforMounted()
            signing.refreshIfPossible(reason: "launch")
            evaluateExpiryWarning()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                signing.refreshIfPossible(reason: "a return to the foreground")
                evaluateExpiryWarning()
            }
        }
        // The tunnel is almost never up at the instant `onAppear` runs, so this is
        // the edge that actually gets the first read of a cold launch taken.
        .onChange(of: tunnel.isConnected) { _, isConnected in
            if isConnected { signing.refreshIfPossible(reason: "the tunnel connecting") }
        }
        // A reading landing seconds after launch is the normal case, so the
        // decision is retried whenever one does rather than only at `onAppear`.
        .onChange(of: signing.reading) { _, _ in
            evaluateExpiryWarning()
        }
        .onReceive(statusTimer) { _ in
            // Cheap existence check only. `prepareURL()` does directory creation and a
            // full byte-compare, which must not run on the main thread once per second.
            pairingExists = FileManager.default.fileExists(atPath: PairingFileStore.url.path)
            if mounting.mountingThread == nil, !mounting.coolisMounted {
                MountingProgress.shared.checkforMounted()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showPairingFilePicker)) { _ in
            isShowingPairingFilePicker = true
        }
    }

    // MARK: - Signing expiry warning

    /// Expiry the card speaks about: whatever the device last told us, or `nil`
    /// when it has never been asked or answered "no profile for this app".
    private var expiryDate: Date? { signing.reading?.expirationDate }

    private var signatureHasExpired: Bool {
        expiryDate.map { AppSigningInfo.hasExpired($0) } ?? false
    }

    /// Decides once per launch whether to warn that the signature is about to
    /// lapse — but only once there is a reading worth deciding on.
    ///
    /// The two ways of knowing nothing are both silence, never a warning:
    ///
    /// * `signing.reading == nil` — the device has never been reachable, so
    ///   there is no expiry, only an absence. A device that cannot be read is
    ///   not a device whose signature has lapsed.
    /// * `signing.reading?.expirationDate == nil` — the device answered and
    ///   carries no profile for this app (App Store or TrollStore install).
    ///
    /// Neither marks the decision as made: a reading can still arrive seconds
    /// later, when the tunnel comes up, and `onChange(of: signing.reading)` calls
    /// back in. Only a trustworthy reading closes the question, and from then on
    /// every early return marks it made, so "Later" holds for the rest of the
    /// session even across foreground/background cycles.
    private func evaluateExpiryWarning() {
        guard !hasEvaluatedExpiryWarning else { return }

        // A reading older than the trust window can only ever cry wolf (an expiry
        // moves later, never earlier), so it is not allowed to raise the card —
        // and it does not settle the question either, because a fresh read may
        // still land this session.
        guard let expiry = signing.reading?.expirationDate, signing.isTrustworthy else { return }

        hasEvaluatedExpiryWarning = true

        guard AppSigningInfo.isExpiringSoon(expiry) else { return }

        // Suppression is keyed to this exact expiry date, so a SideStore refresh —
        // new certificate, new expiry — starts warning again next week. Now that
        // the date is read from the device it actually moves, which is what makes
        // the checkbox mean what it says.
        guard !ExpiryWarningSuppression.isSuppressed(expiry) else { return }

        isShowingExpiryWarning = true
    }

    private func dismissExpiryWarning() {
        if suppressExpiryWarning, let expiry = expiryDate {
            ExpiryWarningSuppression.suppress(expiry)
        }
        isShowingExpiryWarning = false
    }

    private var expiryTitle: String {
        guard let expiry = expiryDate, !AppSigningInfo.hasExpired(expiry) else {
            return String(localized: "MobileGhost has expired")
        }
        let duration = AppSigningInfo.durationPhrase(expiry.timeIntervalSinceNow)
        return String(localized: "MobileGhost expires in \(duration)")
    }

    private var expiryBody: String {
        signatureHasExpired
            ? String(localized: "The signing certificate for this install has lapsed, so MobileGhost will not launch again until it is re-signed. Open SideStore and refresh MobileGhost to fix it.")
            : String(localized: "Open SideStore and refresh MobileGhost to re-sign it. If the signature fully expires the app will not launch and must be reinstalled.")
    }

    /// Same visual language as the readiness overlay: full-screen material scrim
    /// plus a rounded material card. Uses no iOS-26-only API, so it needs no
    /// availability gate — `.regularMaterial` is the floor on iOS 17.4.
    private var expiryOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            expiryCard
                .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    private var expiryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label(expiryTitle, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(signatureHasExpired ? .red : .orange)
                Text(expiryBody)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Refreshing keeps your pairing file and bookmarks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $suppressExpiryWarning) {
                Text("Don't show again for this expiry")
                    .font(.subheadline)
            }

            VStack(spacing: 10) {
                Button {
                    openSideStore()
                    dismissExpiryWarning()
                } label: {
                    Label("Open SideStore", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    dismissExpiryWarning()
                } label: {
                    Text("Later")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(22)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
    }

    // MARK: - Readiness overlay

    /// Full-screen blocking overlay shown until pairing, tunnel and DDI are all up.
    /// The scrim is an opaque-to-touches material layer, so it swallows every tap
    /// that misses the card; the map underneath additionally has hit-testing off.
    private var readinessOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            readinessCard
                .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Device Not Connected", systemImage: "bolt.horizontal.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("MobileGhost needs a connection to this device before it can simulate a location.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                readinessRow(
                    title: String(localized: "Pairing file imported"),
                    isDone: pairingExists,
                    guidance: String(localized: "Import your pairing file.")
                )
                readinessRow(
                    title: String(localized: "Connected to this device"),
                    isDone: tunnel.isConnected,
                    guidance: String(localized: "Open LocalDevVPN and connect the VPN, and make sure Wi-Fi is joined to a network.")
                )
                readinessRow(
                    title: String(localized: "Developer Disk Image mounted"),
                    isDone: mounting.coolisMounted,
                    guidance: String(localized: "Waiting for the Developer Disk Image (DDI) to download and mount."),
                    showsProgress: mounting.mountingThread != nil
                )
            }

            VStack(spacing: 10) {
                Button {
                    isShowingPairingFilePicker = true
                } label: {
                    Label("Import Pairing File", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                // Only useful while the tunnel is down — that is the one failure
                // this button can actually fix.
                if !tunnel.isConnected {
                    Button {
                        openLocalDevVPN()
                    } label: {
                        Label("Open LocalDevVPN", systemImage: "network")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 10) {
                    Button {
                        retryConnection()
                    } label: {
                        // "Retry Connection" wrapped onto two lines in this
                        // half-width slot on a narrow device.
                        Label("Retry", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    // Settings must stay reachable from here: it holds the target IP
                    // field and "Redownload DDI", the recovery tools for this screen.
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(22)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
    }

    private func readinessRow(
        title: String,
        isDone: Bool,
        guidance: String,
        showsProgress: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if showsProgress {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "circle.dashed")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.body)
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isDone ? .secondary : .primary)
                if !isDone {
                    Text(guidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isDone
                ? String(localized: "\(title): done")
                : String(localized: "\(title): pending")
        )
    }

    private func openLocalDevVPN() {
        openFirstResolving(RootViewLinks.localDevVPN)
    }

    private func openSideStore() {
        openFirstResolving(RootViewLinks.sideStore)
    }

    /// The readiness overlay can be on screen with a simulation still running —
    /// `concludeSimulationHasStopped()` puts it there, and so does any tunnel
    /// failure — so this tap has to assume a resend may be mid-handshake. The
    /// tunnel start therefore queues behind whatever the location-simulation
    /// queue is doing rather than racing it for `<targetIP>:49152`; it is
    /// deferred, never dropped. See `startTunnelAfterPendingLocationCommands`.
    ///
    /// The other two are immediate on purpose: they are what makes the tap feel
    /// answered, and neither touches the device's location-simulation service.
    private func retryConnection() {
        markTunnelDisconnected()
        startTunnelAfterPendingLocationCommands()
        MountingProgress.shared.checkforMounted()
    }

    private func importPairingFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                try PairingFileStore.importFromPicker(url)
                pairingExists = true
                markTunnelDisconnected()
                // Same endpoint contention as Retry above: a pairing file can be
                // imported from the readiness overlay with a simulation still
                // running.
                startTunnelAfterPendingLocationCommands()
                AlertPresenter.dismissPresentedAlert()
            } catch {
                LogManager.shared.addErrorLog("Failed to import pairing file: \(error.localizedDescription)")
                showAlert(title: String(localized: "Import Failed"), message: error.localizedDescription, showOk: true)
            }
        case .failure(let error):
            LogManager.shared.addErrorLog("Pairing file picker failed: \(error.localizedDescription)")
        }
    }

}
