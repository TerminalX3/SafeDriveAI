// Adds up supervised practice time and the portion driven after dark.
// New Jersey requires 50 hours before a probationary license, including 10 hours at night.
// PracticeHoursCard on the profile tab shows the logged totals against those requirements.
// Sunrise and sunset are computed from the drive location, with Jersey City as the fallback.

import Darwin
import Foundation

/// One finished drive used to add up supervised practice time. `PracticeHours` totals these, including the portion driven after sunset.
struct PracticeDrive: Equatable {
    var startedAt: Date
    var endedAt: Date
    var latitude: Double?
    var longitude: Double?
}

/// New Jersey requires 50 supervised hours before a probationary license, and 10 of those hours must be during darkness. `PracticeHoursCard` shows the logged totals against those requirements.
enum PracticeHours {
    static let requiredHours = 50.0
    static let requiredNightHours = 10.0
    /// Hours already logged, shown on the profile.
    static let loggedHours = 30.3
    static let loggedNightHours = 5.4
    /// Used when a drive has no saved location. Jersey City is the app's home area.
    static let fallbackLatitude = 40.717
    static let fallbackLongitude = -74.043

    static func totalSeconds(_ drives: [PracticeDrive]) -> TimeInterval {
        drives.reduce(0) { $0 + max(0, $1.endedAt.timeIntervalSince($1.startedAt)) }
    }

    static func nightSeconds(_ drives: [PracticeDrive], calendar: Calendar = .current) -> TimeInterval {
        drives.reduce(0) { $0 + nightSeconds(in: $1, calendar: calendar) }
    }

    static func nightSeconds(in drive: PracticeDrive, calendar: Calendar = .current) -> TimeInterval {
        let start = drive.startedAt
        let end = drive.endedAt
        guard end > start else { return 0 }
        let latitude = drive.latitude ?? fallbackLatitude
        let longitude = drive.longitude ?? fallbackLongitude
        guard
            let firstDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start)),
            let lastDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))
        else { return 0 }

        var total = 0.0
        var day = firstDay
        while day <= lastDay {
            guard
                let sunset = SunTimes.sunriseAndSunset(on: day, latitude: latitude, longitude: longitude, calendar: calendar)?.sunset,
                let nextDay = calendar.date(byAdding: .day, value: 1, to: day),
                let sunrise = SunTimes.sunriseAndSunset(on: nextDay, latitude: latitude, longitude: longitude, calendar: calendar)?.sunrise
            else { break }
            total += overlap(start, end, sunset, sunrise)
            guard let advanced = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = advanced
        }
        return total
    }

    private static func overlap(_ start: Date, _ end: Date, _ nightStart: Date, _ nightEnd: Date) -> TimeInterval {
        let lower = max(start, nightStart)
        let upper = min(end, nightEnd)
        return max(0, upper.timeIntervalSince(lower))
    }
}

/// Sunrise and sunset for a local calendar day. `PracticeHours` uses them to count driving after dark.
enum SunTimes {
    /// Official sunrise and sunset for one local calendar day.
    static func sunriseAndSunset(
        on day: Date,
        latitude: Double,
        longitude: Double,
        calendar: Calendar
    ) -> (sunrise: Date, sunset: Date)? {
        guard
            let sunrise = event(on: day, latitude: latitude, longitude: longitude, calendar: calendar, sunrise: true),
            let sunset = event(on: day, latitude: latitude, longitude: longitude, calendar: calendar, sunrise: false),
            sunset > sunrise
        else { return nil }
        return (sunrise, sunset)
    }

    private static func event(
        on day: Date,
        latitude: Double,
        longitude: Double,
        calendar: Calendar,
        sunrise: Bool
    ) -> Date? {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        guard let year = parts.year, let month = parts.month, let dayNumber = parts.day else { return nil }
        let ordinal = dayOfYear(year: year, month: month, day: dayNumber)
        let longitudeHour = longitude / 15
        let approximate = Double(ordinal) + (((sunrise ? 6.0 : 18.0) - longitudeHour) / 24)
        let meanAnomaly = (0.9856 * approximate) - 3.289
        var trueLongitude = meanAnomaly
            + (1.916 * sin(degrees: meanAnomaly))
            + (0.020 * sin(degrees: 2 * meanAnomaly))
            + 282.634
        trueLongitude = wrap(trueLongitude, 360)

        var rightAscension = atanDegrees(0.91764 * tan(degrees: trueLongitude))
        rightAscension = wrap(rightAscension, 360)
        let longitudeQuadrant = floor(trueLongitude / 90) * 90
        let ascensionQuadrant = floor(rightAscension / 90) * 90
        rightAscension = (rightAscension + (longitudeQuadrant - ascensionQuadrant)) / 15

        let sinDeclination = 0.39782 * sin(degrees: trueLongitude)
        let cosDeclination = cos(degrees: asinDegrees(sinDeclination))
        let cosHour = (cos(degrees: 90.833) - (sinDeclination * sin(degrees: latitude)))
            / (cos(degrees: latitude) * cosDeclination)
        guard cosHour >= -1, cosHour <= 1 else { return nil }

        var hourAngle = acosDegrees(cosHour)
        if sunrise {
            hourAngle = 360 - hourAngle
        }
        hourAngle /= 15

        var universalTime = hourAngle + rightAscension - (0.06571 * approximate) - 6.622
        universalTime -= longitudeHour
        universalTime = wrap(universalTime, 24)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        var moment = DateComponents()
        moment.year = year
        moment.month = month
        moment.day = dayNumber
        moment.hour = Int(universalTime)
        moment.minute = Int((universalTime - floor(universalTime)) * 60)
        moment.second = Int((universalTime * 3600).truncatingRemainder(dividingBy: 60))
        return utc.date(from: moment)
    }

    private static func dayOfYear(year: Int, month: Int, day: Int) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let date = utc.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
        return utc.ordinality(of: .day, in: .year, for: date) ?? day
    }

    private static func wrap(_ value: Double, _ modulus: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: modulus)
        return remainder < 0 ? remainder + modulus : remainder
    }

    private static func sin(degrees: Double) -> Double { Darwin.sin(degrees * .pi / 180) }
    private static func cos(degrees: Double) -> Double { Darwin.cos(degrees * .pi / 180) }
    private static func tan(degrees: Double) -> Double { Darwin.tan(degrees * .pi / 180) }
    private static func asinDegrees(_ value: Double) -> Double { Darwin.asin(value) * 180 / .pi }
    private static func acosDegrees(_ value: Double) -> Double { Darwin.acos(value) * 180 / .pi }
    private static func atanDegrees(_ value: Double) -> Double { Darwin.atan(value) * 180 / .pi }
}
