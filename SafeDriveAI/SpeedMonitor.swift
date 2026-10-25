// Produces the live speed and posted limit shown during a drive.
// Motion is fused with GPS, then the limit is taken from the saved local roads or from an Overpass lookup.
// It can also log raw sensors and write a speed CSV.
// The drive screen and the recorder both read its published values.

import Combine
import CoreLocation
import Foundation

/// How the current speed compares with the posted limit. `SpeedHUD` colors its readout from this.
enum SpeedLimitStatus: Equatable {
    case underLimit
    case atLimit
    case overLimit
    case unknown
}

/// Live speed, posted limit, and location for the drive screen. It fuses motion and GPS, then looks up the limit from saved roads and the map.
final class SpeedMonitor: ObservableObject {
    @Published private(set) var speedMph: Double?
    @Published private(set) var isSpeedInitializing = true
    @Published private(set) var speedLimitMph: Int?
    @Published private(set) var speedLimitIsEstimated = false
    @Published private(set) var isSearchingSpeedLimit = false
    @Published private(set) var status: SpeedLimitStatus = .unknown
    @Published private(set) var authorizationDenied = false
    @Published private(set) var locationMessage: String?
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var headingDegrees: Double?
    @Published private(set) var isLoggingSensors = false
    @Published private(set) var isRecordingSpeedCSV = false
    @Published private(set) var speedRecordingFileName: String?
    @Published private(set) var speedRecordingStartedAt: Date?

    private let motionProvider: MotionDataProvider
    private let locationProvider: LocationDataProvider
    private let logger = DriveSensorLogger()
    private let csvRecorder = SpeedCSVRecorder()
    private let deviceMotion: DeviceMotionProvider?
    private let logSensors: Bool
    private var csvRecording = false

    private let motionQueue = DispatchQueue(label: "SpeedMonitor.fusion", qos: .userInteractive)
    private var displayTimer: Timer?
    private var fusion = SpeedFusion()
    private var hasLocationFix = false
    private var lastLimitQueryLocation: CLLocation?
    private var lastLimitQueryTime: Date = .distantPast
    private var isQueryingLimit = false
    private var limitQueryID = 0
    private var usingSavedLimit = false
    private var lastMapPublishTime = Date.distantPast
    private var lastPublishedCoordinate: CLLocationCoordinate2D?
    private var lastPublishedMph: Double?
    private var lastMainPublish = Date.distantPast
    private var latestLatitude: Double?
    private var latestLongitude: Double?

    private let displayInterval: TimeInterval = 0.05
    private let limitQueryDistance: CLLocationDistance = 30
    private let limitQueryMinInterval: TimeInterval = 12
    private let metersPerSecondToMph = 2.2369362921

    init(
        motion: MotionDataProvider? = nil,
        location: LocationDataProvider? = nil,
        logSensors: Bool = true
    ) {
        if let motion {
            motionProvider = motion
            deviceMotion = nil
        } else {
            let device = DeviceMotionProvider()
            motionProvider = device
            deviceMotion = device
        }
        locationProvider = location ?? DeviceLocationProvider()
        self.logSensors = logSensors
        bindProviders()
    }

    func start() {
        if logSensors {
            logger.start()
            isLoggingSensors = true
        }
        locationProvider.start()
        motionProvider.start()
        fusion.usesNorthReference = deviceMotion?.usesNorthReference ?? true
        applyLocationAuthorization()
        isSpeedInitializing = true
        speedMph = nil
        startDisplayTimer()
    }

    func refreshLocationAccess() {
        locationProvider.start()
        applyLocationAuthorization()
    }

    func startSpeedRecording() {
        guard !isRecordingSpeedCSV else { return }
        let url = csvRecorder.start()
        motionQueue.async { [weak self] in
            guard let self else { return }
            self.csvRecording = url != nil
            if url != nil {
                self.appendSpeedSample(now: Date())
            }
        }
        isRecordingSpeedCSV = url != nil
        speedRecordingFileName = url?.lastPathComponent
        speedRecordingStartedAt = url == nil ? nil : Date()
    }

    func stopSpeedRecording() {
        csvRecorder.stop()
        motionQueue.async { [weak self] in
            self?.csvRecording = false
        }
        isRecordingSpeedCSV = false
        speedRecordingStartedAt = nil
    }

    func toggleSpeedRecording() {
        if isRecordingSpeedCSV {
            stopSpeedRecording()
        } else {
            startSpeedRecording()
        }
    }

    func stop() {
        displayTimer?.invalidate()
        displayTimer = nil
        motionProvider.stop()
        locationProvider.stop()
        logger.stop()
        isLoggingSensors = false
        stopSpeedRecording()
        motionQueue.async { [weak self] in
            self?.fusion.reset()
        }
        hasLocationFix = false
        lastPublishedCoordinate = nil
        speedMph = nil
        isSpeedInitializing = true
    }

    private func bindProviders() {
        motionProvider.onIMU = { [weak self] sample in
            self?.ingestIMU(sample)
        }
        locationProvider.onGPS = { [weak self] sample in
            self?.ingestGPS(sample)
        }
        locationProvider.onAuthorizationChange = { [weak self] in
            DispatchQueue.main.async {
                self?.applyLocationAuthorization()
            }
        }
    }

    private func applyLocationAuthorization() {
        authorizationDenied = locationProvider.authorizationDenied
        locationMessage = locationProvider.locationMessage
    }

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: displayInterval, repeats: true) { [weak self] _ in
            self?.motionQueue.async {
                self?.publishSpeed(force: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func ingestGPS(_ sample: GPSSample) {
        let age = -sample.timestamp.timeIntervalSinceNow
        guard age < 8 else { return }
        guard sample.horizontalAccuracy > 0, sample.horizontalAccuracy <= 120 else { return }

        if logSensors {
            logger.logGPS(sample)
        }

        motionQueue.async { [weak self] in
            guard let self else { return }
            self.latestLatitude = sample.latitude
            self.latestLongitude = sample.longitude
            self.hasLocationFix = true
            if sample.speedMps >= 0 {
                self.fusion.ingestPhoneGPS(sample, now: Date())
            }
            self.publishSpeed(force: true)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.authorizationDenied = self.locationProvider.authorizationDenied
            self.publishMapIfNeeded(from: sample)
            self.maybeRefreshSpeedLimit(from: sample)
        }
    }

    private func ingestIMU(_ sample: IMUSample) {
        if logSensors {
            logger.logIMU(
                accel: sample.deviceAccel,
                rotation: sample.rotation,
                motionTimestamp: sample.motionTimestamp
            )
        }

        motionQueue.async { [weak self] in
            guard let self else { return }
            let world = SpeedFusion.worldUserAcceleration(
                deviceAccel: sample.deviceAccel,
                rotation: sample.rotation
            )
            let along = SpeedFusion.alongTrackAcceleration(
                worldAccel: world,
                courseRadians: self.fusion.courseRadians,
                usesNorthReference: self.fusion.usesNorthReference,
                filteredAccel: self.fusion.filteredAccel
            )
            let now = Date()
            self.fusion.ingestIMU(
                alongTrackAccel: along,
                motionTimestamp: sample.motionTimestamp,
                now: now
            )
            self.appendSpeedSample(now: now)
            self.publishSpeed(force: false)
        }
    }

    private func appendSpeedSample(now: Date) {
        guard csvRecording else { return }
        let speed: Double?
        if !hasLocationFix {
            speed = nil
        } else if fusion.isStationary {
            speed = 0
        } else {
            speed = fusion.speedMps
        }
        csvRecorder.append(
            now: now,
            speedMps: speed,
            gpsMps: fusion.lastGpsSpeed,
            accelMps2: fusion.filteredAccel,
            stationary: fusion.isStationary,
            latitude: latestLatitude,
            longitude: latestLongitude
        )
    }

    private func publishSpeed(force: Bool) {
        let ready = fusion.isDisplayReady
        let mph: Double?
        if !ready {
            mph = nil
        } else if fusion.isStationary {
            mph = 0
        } else {
            mph = fusion.speedMps * metersPerSecondToMph
        }

        let initializing = !ready
        let now = Date()
        let integerChanged = Int((mph ?? -1).rounded()) != Int((lastPublishedMph ?? -2).rounded())
        guard force || integerChanged || now.timeIntervalSince(lastMainPublish) >= displayInterval else {
            return
        }
        lastMainPublish = now
        lastPublishedMph = mph

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isSpeedInitializing != initializing {
                self.isSpeedInitializing = initializing
            }
            if self.speedMph != mph {
                self.speedMph = mph
                self.recalculateStatus()
            }
        }
    }

    private func publishMapIfNeeded(from sample: GPSSample) {
        let now = Date()
        let coordinate = CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)
        let moved: CLLocationDistance
        if let last = lastPublishedCoordinate {
            moved = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        } else {
            moved = .greatestFiniteMagnitude
        }

        let headingChanged: Bool
        if sample.courseAccuracy >= 0, sample.courseDegrees >= 0 {
            let previous = headingDegrees ?? sample.courseDegrees
            headingChanged = abs(previous - sample.courseDegrees) > 8
        } else {
            headingChanged = false
        }

        guard moved >= 6 || headingChanged || now.timeIntervalSince(lastMapPublishTime) >= 1.0 else {
            return
        }

        self.coordinate = coordinate
        lastPublishedCoordinate = coordinate
        lastMapPublishTime = now
        if sample.courseAccuracy >= 0, sample.courseDegrees >= 0 {
            headingDegrees = sample.courseDegrees
        }
    }

    private func recalculateStatus() {
        guard let speedMph, let speedLimitMph else {
            status = .unknown
            return
        }

        let roundedSpeed = Int(speedMph.rounded())
        if roundedSpeed > speedLimitMph {
            status = .overLimit
        } else if roundedSpeed == speedLimitMph {
            status = .atLimit
        } else {
            status = .underLimit
        }
    }

    private func maybeRefreshSpeedLimit(from sample: GPSSample) {
        let location = CLLocation(latitude: sample.latitude, longitude: sample.longitude)
        if let saved = SavedRoadLimits.mph(at: location.coordinate) {
            usingSavedLimit = true
            limitQueryID += 1
            isQueryingLimit = false
            isSearchingSpeedLimit = false
            if speedLimitMph != saved || speedLimitIsEstimated {
                apply(SpeedLimitResult(mph: saved, isEstimated: false))
            }
            return
        }
        if usingSavedLimit {
            usingSavedLimit = false
            speedLimitMph = nil
            speedLimitIsEstimated = false
            lastLimitQueryLocation = nil
            isSearchingSpeedLimit = true
        }
        guard !isQueryingLimit else { return }
        let stillEstimating = speedLimitMph == nil || speedLimitIsEstimated
        let wait = stillEstimating ? 6.0 : limitQueryMinInterval
        let move = stillEstimating ? 12.0 : limitQueryDistance
        if let last = lastLimitQueryLocation {
            let movedFarEnough = location.distance(from: last) >= move
            let waitedLongEnough = Date().timeIntervalSince(lastLimitQueryTime) >= wait
            guard movedFarEnough || waitedLongEnough else { return }
        }

        isQueryingLimit = true
        if speedLimitMph == nil {
            isSearchingSpeedLimit = true
        }
        lastLimitQueryLocation = location
        lastLimitQueryTime = Date()
        limitQueryID += 1
        let queryID = limitQueryID
        let coordinate = location.coordinate

        Task {
            async let posted = SpeedLimitLookup.postedLimit(at: coordinate)
            async let estimated = SpeedLimitLookup.estimatedLimit(at: coordinate)

            if let estimate = await estimated {
                await MainActor.run {
                    guard self.limitQueryID == queryID else { return }
                    if self.speedLimitMph == nil || self.speedLimitIsEstimated {
                        self.apply(estimate)
                    }
                }
            }

            let postedLimit = await posted
            await MainActor.run {
                guard self.limitQueryID == queryID else { return }
                self.isQueryingLimit = false
                self.isSearchingSpeedLimit = false
                if let postedLimit {
                    self.apply(postedLimit)
                }
            }
        }
    }

    private func apply(_ limit: SpeedLimitResult) {
        speedLimitMph = limit.mph
        speedLimitIsEstimated = limit.isEstimated
        isSearchingSpeedLimit = false
        if locationMessage == "No posted speed limit for this road."
            || locationMessage == "Speed limit unavailable for this road." {
            locationMessage = nil
        }
        recalculateStatus()
    }
}

/// A posted speed in miles per hour, and whether it came from an estimate rather than a mapped sign.
private struct SpeedLimitResult {
    let mph: Int
    let isEstimated: Bool
}

/// Asks Overpass for the nearest road's `maxspeed` tag. `SpeedMonitor` calls it when no saved local limit applies.
private enum SpeedLimitLookup {
    private static let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter"
    ]

    /// Posted limit from the nearest mapped roads. A small tag-only query, because
    /// asking for full road geometry times out before a limit can be shown.
    static func postedLimit(at coordinate: CLLocationCoordinate2D) async -> SpeedLimitResult? {
        let lat = String(format: "%.5f", coordinate.latitude)
        let lon = String(format: "%.5f", coordinate.longitude)
        let query = """
        [out:json][timeout:8];
        way(around:32,\(lat),\(lon))["highway"]["maxspeed"];
        out tags 5;
        """
        return await withTaskGroup(of: SpeedLimitResult?.self) { group in
            for endpoint in endpoints {
                group.addTask {
                    guard let data = await post(endpoint: endpoint, query: query) else { return nil }
                    return parsePosted(data)
                }
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    /// A typical limit for this kind of road, available in well under a second.
    static func estimatedLimit(at coordinate: CLLocationCoordinate2D) async -> SpeedLimitResult? {
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/reverse")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "lat", value: String(format: "%.5f", coordinate.latitude)),
            URLQueryItem(name: "lon", value: String(format: "%.5f", coordinate.longitude)),
            URLQueryItem(name: "zoom", value: "17"),
            URLQueryItem(name: "addressdetails", value: "1")
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("SafeDriveAI/1.0 (Congressional App Challenge)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return parseNominatim(data)
        } catch {
            return nil
        }
    }

    private static func post(endpoint: String, query: String) async -> Data? {
        guard let url = URL(string: endpoint) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("SafeDriveAI/1.0 (Congressional App Challenge)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [URLQueryItem(name: "data", value: query)]
        request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private static func parsePosted(_ data: Data) -> SpeedLimitResult? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let elements = json["elements"] as? [[String: Any]]
        else {
            return nil
        }

        var votes: [Int: Int] = [:]
        for element in elements {
            guard let tags = stringTags(element["tags"]) else { continue }
            let mph = parseMaxSpeed(tags["maxspeed"])
                ?? parseMaxSpeed(tags["maxspeed:forward"])
                ?? parseMaxSpeed(tags["maxspeed:backward"])
            guard let mph else { continue }
            votes[mph, default: 0] += 1
        }
        guard let best = votes.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key > rhs.key
        }) else {
            return nil
        }
        return SpeedLimitResult(mph: best.key, isEstimated: false)
    }

    private static func parseNominatim(_ data: Data) -> SpeedLimitResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let category = json["category"] as? String
        let type = (json["type"] as? String) ?? ""
        if category == "highway" {
            return SpeedLimitResult(mph: estimatedLimit(for: type), isEstimated: true)
        }
        let address = json["address"] as? [String: Any]
        guard address?["road"] != nil else { return nil }
        return SpeedLimitResult(mph: 30, isEstimated: true)
    }

    private static func estimatedLimit(for highway: String) -> Int {
        switch highway {
        case "motorway", "motorway_link": return 70
        case "trunk", "trunk_link": return 55
        case "primary", "primary_link": return 45
        case "secondary", "secondary_link": return 40
        case "tertiary", "tertiary_link": return 35
        case "unclassified", "residential": return 25
        case "living_street", "service": return 15
        default: return 25
        }
    }

    private static func stringTags(_ value: Any?) -> [String: String]? {
        guard let raw = value as? [String: Any], !raw.isEmpty else { return nil }
        var tags: [String: String] = [:]
        for (key, item) in raw {
            if let text = item as? String {
                tags[key] = text
            } else if let number = item as? NSNumber {
                tags[key] = number.stringValue
            }
        }
        return tags.isEmpty ? nil : tags
    }

    private static func parseMaxSpeed(_ raw: String?) -> Int? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty else {
            return nil
        }
        if ["signals", "none", "unposted", "walk", "variable"].contains(value) { return nil }
        if value == "national" { return 55 }

        let isKmh = value.contains("km")
        let isMph = value.contains("mph")
        value = value.replacingOccurrences(of: "km/h", with: "")
            .replacingOccurrences(of: "kmh", with: "")
            .replacingOccurrences(of: "kph", with: "")
            .replacingOccurrences(of: "mph", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let number = Double(value.split(separator: " ").first.map(String.init) ?? value) else {
            return nil
        }

        if isKmh {
            return Int((number * 0.621371).rounded())
        }
        if isMph || number <= 85 {
            return Int(number.rounded())
        }
        return Int((number * 0.621371).rounded())
    }

}
