// Mobile Ghost additions, 2026-10-22. AGPL-3.0.
import SwiftUI
import MapKit

extension GeoPoint {
    init(_ c: CLLocationCoordinate2D) { latitude = c.latitude; longitude = c.longitude }
    var coordinate: CLLocationCoordinate2D { .init(latitude:latitude,longitude:longitude) }
}

@MainActor final class GhostSession: ObservableObject {
    @Published var status = "Ready to select a location"
    @Published var error: String?
    @Published var busy = false
    @Published var current: GeoPoint?
    @Published var running = false
    @Published var speed = 5.0
    @Published var scheduled: Date?
    @Published var needsRestore = UserDefaults.standard.bool(forKey:"ghostNeedsRestore")
    private var cursor: JourneyCursor?
    private var scheduledPlan: JourneyPlan?
    private var scheduledSpeed = 5.0
    private var timer: Timer?
    private var lastTick = Date()
    private var foreground = true
    private var refreshEnabled = false
    init() {
        if needsRestore { status = "Previous session needs review. Reconnect and restore." }
        if let data = UserDefaults.standard.data(forKey:"ghostLastPoint") { current = try? JSONDecoder().decode(GeoPoint.self,from:data) }
        timer = Timer.scheduledTimer(withTimeInterval:1, repeats:true) { [weak self] _ in Task { @MainActor in await self?.tick() } }
    }
    func setForeground(_ active: Bool) {
        foreground = active
        if !active {
            if scheduled != nil { cancelSchedule(); status = "Departure cancelled: app left foreground. Review and reschedule." }
            if needsRestore && !BackgroundLocationManager.shared.canContinueInBackground {
                running = false
                status = "Background location permission needed. Last simulated position may remain."
            }
        }
        // Preserve the timestamp: returning after actual suspension must not hide
        // a missed interval and silently resume movement.

    }
    private func command(_ point: GeoPoint?) async -> Int32 {
        let ip = DeviceConnectionContext.targetIPAddress
        let path = PairingFileStore.prepareURL().path
        return await withCheckedContinuation { continuation in
            LocationSimulationCommandQueue.shared.async {
                let code: Int32
                if let point { code = simulate_location(ip,point.latitude,point.longitude,path) }
                else { code = clear_simulated_location() }
                continuation.resume(returning:code)
            }
        }
    }
    private func accepted(_ point: GeoPoint) {
        current = point; needsRestore = true; refreshEnabled = true
        UserDefaults.standard.set(true,forKey:"ghostNeedsRestore")
        UserDefaults.standard.set(try? JSONEncoder().encode(point),forKey:"ghostLastPoint")
        LocationSimulationSession.setMaintained(true)
        if foreground { BackgroundLocationManager.shared.requestStart() }
    }
    private func failure(_ code: Int32) {
        running = false; refreshEnabled = false
        BackgroundLocationManager.shared.requestStop()
        error = "Device operation failed (\(code)). Reconnect LocalDevVPN and retry. The last simulated location may remain."
        status = "Connection needs attention"
    }
    func setLocation(_ point: GeoPoint) async {
        guard !busy, point.isValid else { return }
        cancelSchedule(); running = false; cursor = nil; busy = true
        defer { busy = false }
        BackgroundLocationManager.shared.requestStart()
        let code = await command(point)
        if code == 0 { accepted(point); status = "Holding selected location — command accepted" } else { failure(code) }
    }
    func start(_ plan: JourneyPlan) async {
        guard !busy, plan.isValid else { return }
        cancelSchedule(); running = false; busy = true
        defer { busy = false }
        BackgroundLocationManager.shared.requestStart()
        let next = JourneyCursor(plan:plan,speed:speed)
        let code = await command(next.point)
        if code == 0 { cursor = next; speed = next.speed; accepted(next.point); running = foreground || BackgroundLocationManager.shared.canContinueInBackground; lastTick = Date(); status = running ? "Following route" : "Paused — background location permission needed" }
        else { failure(code) }
    }
    func pause() { running = false; status = "Paused — holding last location" }
    func resume() {
        guard !busy, let cursor, !cursor.finished, foreground else { return }
        BackgroundLocationManager.shared.requestStart()
        cancelSchedule(); refreshEnabled = true; running = true; lastTick = Date(); status = "Following route"
    }
    var canResume: Bool { cursor != nil && cursor?.finished == false && !running }
    func applySpeed(_ value: Double) {
        guard value.isFinite, (1...160).contains(value), !busy else { return }
        speed = value; cursor?.speed = value
    }
    func schedule(_ plan: JourneyPlan, at date: Date) {
        guard !busy, plan.isValid, date.timeIntervalSinceNow > 0, date.timeIntervalSinceNow <= 30*86400 else { error = "Choose a departure within the next 30 days."; return }
        scheduledPlan = plan; scheduledSpeed = speed; scheduled = date
        status = "Departure armed. Keep this app open and the phone awake."
    }
    func cancelSchedule() { scheduled = nil; scheduledPlan = nil }
    func restore() async {
        guard !busy else { return }
        cancelSchedule(); running = false; busy = true
        defer { busy = false }
        // After process restart, reopen a session at the last acknowledged point before clearing.
        if !LocationSimulationSession.isOpen, let current {
            let code = await command(current)
            guard code == 0 else { failure(code); return }
        }
        let code = await command(nil)
        if code == 0 {
            cursor = nil; current = nil; needsRestore = false; refreshEnabled = false
            LocationSimulationSession.setMaintained(false)
            BackgroundLocationManager.shared.requestStop()
            UserDefaults.standard.removeObject(forKey:"ghostLastPoint")
            UserDefaults.standard.set(false,forKey:"ghostNeedsRestore")
            status = "Restore accepted. Check Maps for your real position."
        } else { failure(code) }
    }
    private func tick() async {
        let now = Date(); let elapsed = now.timeIntervalSince(lastTick); lastTick = now
        guard BackgroundExecutionPolicy.mayTick(foreground: foreground, locationActive: BackgroundLocationManager.shared.canContinueInBackground) else {
            if running { pause(); status = "Paused — background location permission needed" }
            return
        }
        if foreground, let due = scheduled, now >= due {
            guard !busy, now.timeIntervalSince(due) <= 60, let plan = scheduledPlan,
                  TunnelManager.shared.isConnected, MountingProgress.shared.coolisMounted else {
                cancelSchedule(); status = "Missed departure. Review connection and reschedule."; return
            }
            speed = scheduledSpeed; await start(plan); return
        }
        guard !busy, refreshEnabled, needsRestore, let point = current else { return }
        if running && BackgroundExecutionPolicy.interrupted(elapsed: elapsed) { pause(); status = "Paused after a delayed update. Resume to continue."; return }
        let wasRunning = running
        var next = cursor
        if running { next?.advance(seconds:min(2,elapsed)) }
        let target = running ? (next?.point ?? point) : point
        busy = true
        let code = await command(target)
        busy = false
        if code == 0 {
            accepted(target)
            if wasRunning { cursor = next; speed = next?.speed ?? speed; if next?.finished == true { running = false; status = "Arrived — holding destination" } }
        } else { failure(code) }
    }
}
