// Mobile Ghost additions, 2026-10-22. AGPL-3.0.
import SwiftUI
import MapKit

struct GhostHomeView: View {
    @StateObject private var session = GhostSession()
    @Environment(\.scenePhase) private var phase
    @State private var camera: MapCameraPosition = .automatic
    @State private var centre = GeoPoint(latitude:43.6532,longitude:-79.3832)
    @State private var selected: GeoPoint?
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var stops: [JourneyStop] = []
    @State private var nearby: [JourneyStop] = []
    @State private var saved: [JourneyStop] = []
    @State private var mode = "Walking"
    @State private var plan: JourneyPlan?
    @State private var working = false
    @State private var showSettings = false
    @State private var showLibrary = false
    @State private var showRoute = false
    @State private var departure = Date().addingTimeInterval(300)
    @State private var speed = 5.0
    @State private var nextTransitQuery = Date.distantPast

    var body: some View {
        VStack(spacing:0) {
            header
            ZStack(alignment:.top) {
                MapReader { proxy in
                    Map(position:$camera) {
                        if let selected { Marker("Selected",systemImage:"mappin.circle.fill",coordinate:selected.coordinate).tint(.purple) }
                        if let current = session.current { Annotation("Simulated",coordinate:current.coordinate) { Image(systemName:"location.fill").padding(10).background(.mint,in:Circle()).foregroundStyle(.black) } }
                        ForEach(Array(stops.enumerated()),id:\.element.id) { index, stop in Marker("\(index+1). \(stop.name)",coordinate:stop.point.coordinate).tint(.indigo) }
                        ForEach(nearby) { stop in Annotation(stop.name,coordinate:stop.point.coordinate) { Button { select(stop.point); query = stop.name } label: { Image(systemName:"bus.fill").padding(8).background(.blue,in:Circle()).foregroundStyle(.white) }.accessibilityLabel("Select bus stop \(stop.name)") } }
                        if let plan { ForEach(plan.legs.indices,id:\.self) { i in MapPolyline(coordinates:plan.legs[i].points.map(\.coordinate)).stroke(.purple,lineWidth:5) } }
                    }
                    .onMapCameraChange(frequency:.onEnd) { centre = GeoPoint($0.region.center) }
                    .onTapGesture { location in if let c = proxy.convert(location,from:.local) { selected = GeoPoint(c) } }
                }
                VStack(spacing:0) {
                    HStack {
                        Image(systemName:"magnifyingglass")
                        TextField("Search place or latitude, longitude",text:$query).submitLabel(.search).onSubmit { Task { await search() } }
                        Button { Task { await search() } } label: { Image(systemName:"arrow.right.circle.fill") }.disabled(working || query.isEmpty).accessibilityLabel("Search")
                    }.padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16))
                    if !results.isEmpty {
                        VStack(alignment:.leading) {
                            ForEach(Array(results.prefix(4).enumerated()),id:\.offset) { _, item in
                                Button { select(GeoPoint(item.placemark.coordinate)); query = item.name ?? "Place"; results = [] } label: { Text(item.name ?? "Place").frame(maxWidth:.infinity,alignment:.leading).padding(10) }
                            }
                        }.background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))
                    }
                }.padding(12)
            }.frame(minHeight:180)
            controlPanel
        }
        .background(Color(uiColor:.systemGroupedBackground))
        .toolbar(.hidden,for:.navigationBar)
        .tint(.purple)
        .sheet(isPresented:$showSettings) { SettingsView() }
        .sheet(isPresented:$showRoute) { routeEditor }
        .sheet(isPresented:$showLibrary) { library }
        .alert("Mobile Ghost",isPresented:Binding(get:{session.error != nil},set:{if !$0 { session.error = nil }})) { Button("OK") {session.error = nil} } message: { Text(session.error ?? "") }
        .onAppear {
            if let data = UserDefaults.standard.data(forKey:"ghostPlaces") { saved = (try? JSONDecoder().decode([JourneyStop].self,from:data)) ?? [] }
            camera = .region(MKCoordinateRegion(center:centre.coordinate,latitudinalMeters:3000,longitudinalMeters:3000))
        }
        .onChange(of:phase) { _, value in session.setForeground(value == .active); UIApplication.shared.isIdleTimerDisabled = value == .active && (session.needsRestore || session.scheduled != nil) }
        .onChange(of:session.needsRestore) { _, _ in updateAwake() }
        .onChange(of:session.scheduled) { _, _ in updateAwake() }
    }
    private func updateAwake() { UIApplication.shared.isIdleTimerDisabled = phase == .active && (session.needsRestore || session.scheduled != nil) }
    private var header: some View {
        HStack {
            Image(systemName:"location.north.circle.fill").font(.title).foregroundStyle(.purple)
            VStack(alignment:.leading,spacing:2) { Text("MOBILE GHOST").font(.headline); Text("Location studio").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button { showLibrary = true } label: { Image(systemName:"bookmark") }.accessibilityLabel("Saved places")
            Button { showSettings = true } label: { Image(systemName:"gearshape") }.padding(.leading,12).accessibilityLabel("Connection settings")
        }.padding()
    }
    private var controlPanel: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:12) {
                HStack { Circle().fill(session.running ? .green : .orange).frame(width:8,height:8); Text(session.status).font(.caption); if session.busy || working { ProgressView() } }
                if let p = selected {
                    HStack {
                        Text(String(format:"%.5f, %.5f",p.latitude,p.longitude)).font(.subheadline.monospaced())
                        Spacer()
                        Button { saved.append(JourneyStop(name:query.isEmpty ? "Saved place \(saved.count+1)" : query,point:p)); persistPlaces() } label: { Image(systemName:"bookmark.badge.plus") }.accessibilityLabel("Save selected place")
                    }
                    HStack {
                        Button("Set location") { Task { await session.setLocation(p) } }.buttonStyle(.borderedProminent).disabled(session.busy)
                        Button("Add route stop") { if stops.count < 12 { stops.append(JourneyStop(name:query.isEmpty ? "Stop \(stops.count+1)" : query,point:p)); plan = nil } }.buttonStyle(.bordered).disabled(stops.count >= 12 || working)
                    }
                } else { Text("Tap the map to choose a location.").foregroundStyle(.secondary) }
                HStack {
                    Button("Route · \(stops.count) stops",systemImage:"point.topleft.down.to.point.bottomright.curvepath") { showRoute = true }
                    Spacer()
                    Button("Bus stops",systemImage:"bus") { Task { await findBusStops() } }.disabled(working)
                }.font(.subheadline)
                HStack {
                    Text("\(Int(speed)) km/h").monospacedDigit().frame(width:78,alignment:.leading)
                    Slider(value:$speed,in:1...160,step:1)
                    Button("Apply") { session.applySpeed(speed) }.disabled(session.busy)
                }
                HStack {
                    if session.running { Button("Pause",systemImage:"pause.fill") { session.pause() }.buttonStyle(.bordered) }
                    if session.canResume { Button("Resume",systemImage:"play.fill") { session.resume() }.buttonStyle(.bordered).disabled(session.busy) }
                    Spacer()
                    Button("Restore real location",systemImage:"location") { Task { await session.restore() } }.buttonStyle(.bordered).disabled(!session.needsRestore || session.busy)
                }
                if let date = session.scheduled { HStack { Text("Departure: \(date.formatted(date:.abbreviated,time:.shortened))"); Button("Cancel") { session.cancelSchedule() } }.font(.caption) }
            }.padding()
        }.frame(maxHeight:300)
    }
    private var routeEditor: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    Picker("Travel mode",selection:$mode) { Text("Walking").tag("Walking"); Text("Car").tag("Car"); Text("Bus (custom roads)").tag("Bus") }
                        .onChange(of:mode) { _, m in plan = nil; speed = m == "Walking" ? 5 : (m == "Car" ? 40 : 30) }
                    Text("Add 2–12 pins from the map. Bus mode follows roads between your selected stops, not an official transit service.").font(.caption).foregroundStyle(.secondary)
                    ForEach($stops) { $stop in
                        VStack(alignment:.leading) {
                            Text(stop.name).font(.headline)
                            HStack { Text("Wait (seconds)"); TextField("0",value:$stop.waitSeconds,format:.number).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                            HStack { Text("Depart (km/h, 0 = inherit)"); TextField("0",value:$stop.departureSpeed,format:.number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        }
                    }.onDelete { stops.remove(atOffsets:$0); plan = nil }.onMove { stops.move(fromOffsets:$0,toOffset:$1); plan = nil }
                    Button(working ? "Planning…" : "Plan route") { Task { await planRoute() } }.disabled(stops.count < 2 || working)
                }.disabled(session.busy || working)
                if let plan {
                    Section("Ready to travel") {
                        Text(String(format:"%.2f km · %@",plan.distance/1000,plan.mode))
                        Text("Start moves the phone to the first stop. Keep Mobile Ghost visible; leaving the app pauses movement.").font(.caption)
                        Button("Start route") { let snapshot = JourneyPlan(stops:stops,legs:plan.legs,mode:mode); session.applySpeed(speed); Task { await session.start(snapshot) }; showRoute = false }.disabled(session.busy || !timingsValid)
                        DatePicker("Departure",selection:$departure,in:Date()...Date().addingTimeInterval(30*86400))
                        Button("Schedule departure") { session.applySpeed(speed); session.schedule(JourneyPlan(stops:stops,legs:plan.legs,mode:mode),at:departure); showRoute = false }.disabled(session.busy || !timingsValid)
                    }
                }
                if !timingsValid { Text("Waits must be 0–86,400 seconds. Departure speed must be 0 (inherit) or 1–160 km/h.").foregroundStyle(.red) }
            }
            .navigationTitle("Plan a journey")
            .toolbar { ToolbarItem(placement:.topBarLeading) { EditButton() }; ToolbarItem(placement:.topBarTrailing) { Button("Done") { showRoute = false } } }
        }
    }
    private var timingsValid: Bool { stops.allSatisfy { (0...86400).contains($0.waitSeconds) && ($0.departureSpeed == 0 || (1...160).contains($0.departureSpeed)) } }
    private var library: some View {
        NavigationStack {
            List {
                Section("Saved places") { ForEach(saved) { place in Button(place.name) { select(place.point); query = place.name; showLibrary = false } }.onDelete { saved.remove(atOffsets:$0); persistPlaces() } }
                Section("About") {
                    Text("Mobile Ghost 0.1.0 · iPhone location simulation")
                    Text("Independent derivative of TLocation and StikDebug. © Stephen Bove and contributors. Modified October 22, 2026. AGPL-3.0; no warranty.").font(.caption)
                    Link("Source code and license",destination:URL(string:"https://github.com/rehanjafar/mobile-ghost")!)
                }
            }.navigationTitle("Library").toolbar { Button("Done") { showLibrary = false } }
        }
    }
    private func persistPlaces() { UserDefaults.standard.set(try? JSONEncoder().encode(saved),forKey:"ghostPlaces") }
    private func select(_ point: GeoPoint) { selected = point; camera = .region(MKCoordinateRegion(center:point.coordinate,latitudinalMeters:1500,longitudinalMeters:1500)) }
    private func search() async {
        guard !working else { return }; working = true; defer { working = false }
        let values = query.split(separator:",").compactMap { Double($0.trimmingCharacters(in:.whitespaces)) }
        if values.count == 2 { let p = GeoPoint(latitude:values[0],longitude:values[1]); if p.isValid { select(p); results = []; return } }
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center:centre.coordinate,latitudinalMeters:10000,longitudinalMeters:10000)
        do { results = try await MKLocalSearch(request:request).start().mapItems; if results.isEmpty { session.error = "No matching places found." } } catch { session.error = error.localizedDescription }
    }
    private func planRoute() async {
        guard !working, stops.count >= 2, timingsValid else { return }
        working = true; plan = nil; defer { working = false }
        let snapshot = stops; let selectedMode = mode
        do {
            var legs: [JourneyLeg] = []
            for (a,b) in zip(snapshot,snapshot.dropFirst()) {
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark:MKPlacemark(coordinate:a.point.coordinate))
                request.destination = MKMapItem(placemark:MKPlacemark(coordinate:b.point.coordinate))
                request.transportType = selectedMode == "Walking" ? .walking : .automobile
                guard let route = try await MKDirections(request:request).calculate().routes.first else { throw URLError(.cannotParseResponse) }
                let line = route.polyline
                let points = (0..<line.pointCount).map { GeoPoint(line.points()[$0].coordinate) }
                guard points.count >= 2 else { throw URLError(.cannotParseResponse) }
                legs.append(JourneyLeg(points:points))
            }
            guard stops == snapshot, mode == selectedMode else { return }
            plan = JourneyPlan(stops:snapshot,legs:legs,mode:selectedMode)
        } catch { session.error = "Route could not be planned: \(error.localizedDescription). Choose points on connected roads or paths." }
    }
    private func findBusStops() async {
        guard !working else { return }
        guard Date() >= nextTransitQuery else { session.error = "Wait 30 seconds between bus-stop searches."; return }
        working = true; nextTransitQuery = Date().addingTimeInterval(30); defer { working = false }
        let q = "[out:json][timeout:20];(node[highway=bus_stop](around:1000,\(centre.latitude),\(centre.longitude));node[public_transport=platform][bus=yes](around:1000,\(centre.latitude),\(centre.longitude)););out body 500;"
        var request = URLRequest(url:URL(string:"https://overpass-api.de/api/interpreter")!); request.httpMethod = "POST"; request.timeoutInterval = 30
        var form = URLComponents(); form.queryItems = [URLQueryItem(name:"data",value:q)]; request.httpBody = form.percentEncodedQuery?.data(using:.utf8)
        request.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")
        struct Response: Decodable { struct Node: Decodable { var lat: Double; var lon: Double; var tags: [String:String]? }; var elements: [Node] }
        do {
            let (data,response) = try await URLSession.shared.data(for:request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 2_000_000 else { throw URLError(.badServerResponse) }
            let nodes = try JSONDecoder().decode(Response.self,from:data).elements
            nearby = nodes.prefix(500).map { JourneyStop(name:$0.tags?["name"] ?? "Bus stop",point:GeoPoint(latitude:$0.lat,longitude:$0.lon)) }.filter { $0.point.isValid }
            if nearby.isEmpty { session.error = "No mapped bus stops found within 1 km of the map centre." }
        } catch { session.error = "Bus-stop search failed: \(error.localizedDescription)" }
    }
}
