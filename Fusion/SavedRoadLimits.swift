// Returns posted speed limits for a few Jersey City roads before any online map lookup.
// Chapel Avenue and Caven Point Road are 25 mph.
// Linden Avenue East and the rest of Port Liberte are 15 mph.
// SpeedMonitor checks this table first.

import CoreLocation
import Foundation

/// Posted limits `SpeedMonitor` checks before the online map lookup. Chapel Avenue and Caven Point Road in Jersey City are 25 mph for their whole length. Linden Avenue East is 15 mph, and every other road inside Port Liberte is 15 mph.
enum SavedRoadLimits {
    /// How close the car must be to a saved road's centerline.
    static let matchMeters: CLLocationDistance = 35

    static let chapelAvenue: [[(Double, Double)]] = [
        [
            (40.692877, -74.080980),
            (40.692430, -74.080378),
            (40.692216, -74.080095),
            (40.691665, -74.079366),
            (40.690726, -74.078124),
            (40.690498, -74.077826),
            (40.690131, -74.077399),
            (40.689786, -74.077025),
            (40.689577, -74.076791),
            (40.689380, -74.076553),
            (40.689027, -74.076091),
            (40.688370, -74.075212),
        ],
        [
            (40.685197, -74.070839),
            (40.685214, -74.070866),
            (40.685324, -74.071035),
            (40.685458, -74.071246),
            (40.685541, -74.071377),
            (40.685734, -74.071677),
            (40.685810, -74.071788),
            (40.685884, -74.071890),
            (40.686080, -74.072151),
            (40.686293, -74.072426),
            (40.686350, -74.072503),
            (40.686421, -74.072599),
            (40.686536, -74.072749),
            (40.686602, -74.072834),
            (40.687101, -74.073495),
            (40.687379, -74.073866),
            (40.687563, -74.074110),
            (40.687583, -74.074136),
            (40.687612, -74.074176),
            (40.687642, -74.074217),
            (40.687644, -74.074219),
            (40.687646, -74.074222),
        ],
        [
            (40.699384, -74.089380),
            (40.698383, -74.088212),
            (40.697790, -74.087499),
            (40.697730, -74.087427),
        ],
        [
            (40.694828, -74.083514),
            (40.694650, -74.083289),
            (40.694090, -74.082568),
            (40.694060, -74.082530),
            (40.693452, -74.081749),
            (40.693385, -74.081651),
        ],
        [
            (40.697730, -74.087427),
            (40.697696, -74.087307),
            (40.697639, -74.087234),
            (40.697581, -74.087155),
            (40.697536, -74.087083),
            (40.696291, -74.085452),
            (40.696277, -74.085433),
            (40.696221, -74.085359),
        ],
        [
            (40.687646, -74.074222),
            (40.687790, -74.074412),
        ],
        [
            (40.687981, -74.074676),
            (40.687917, -74.074587),
            (40.687801, -74.074427),
            (40.687790, -74.074412),
        ],
        [
            (40.688370, -74.075212),
            (40.688148, -74.074907),
        ],
        [
            (40.688148, -74.074907),
            (40.688037, -74.074754),
            (40.687981, -74.074676),
        ],
        [
            (40.685197, -74.070839),
            (40.685036, -74.070593),
            (40.685022, -74.070569),
            (40.685012, -74.070540),
            (40.685010, -74.070513),
            (40.685012, -74.070487),
            (40.685019, -74.070459),
            (40.685033, -74.070433),
            (40.685049, -74.070414),
            (40.685070, -74.070399),
            (40.685094, -74.070389),
            (40.685117, -74.070388),
            (40.685140, -74.070394),
            (40.685159, -74.070407),
            (40.685176, -74.070428),
            (40.685187, -74.070452),
            (40.685195, -74.070479),
            (40.685200, -74.070514),
            (40.685200, -74.070545),
            (40.685197, -74.070746),
            (40.685197, -74.070839),
        ],
    ]

    static let cavenPointRoad: [[(Double, Double)]] = [
        [
            (40.693458, -74.081579),
            (40.693716, -74.081323),
            (40.694045, -74.081016),
            (40.694383, -74.080700),
            (40.694688, -74.080383),
            (40.694972, -74.080067),
            (40.695221, -74.079761),
            (40.695461, -74.079445),
            (40.695562, -74.079278),
            (40.695652, -74.079112),
            (40.695725, -74.078914),
            (40.695778, -74.078704),
            (40.695814, -74.078501),
            (40.695863, -74.077900),
            (40.695912, -74.077594),
            (40.696004, -74.077278),
            (40.696107, -74.077031),
            (40.696250, -74.076789),
            (40.696404, -74.076591),
            (40.696579, -74.076414),
            (40.697116, -74.075974),
            (40.697270, -74.075829),
            (40.697425, -74.075641),
            (40.697559, -74.075437),
            (40.697685, -74.075164),
            (40.697799, -74.074874),
            (40.697893, -74.074558),
            (40.698991, -74.070578),
            (40.699056, -74.070390),
            (40.699166, -74.070052),
            (40.699296, -74.069756),
            (40.699463, -74.069462),
            (40.699587, -74.069275),
            (40.699633, -74.069204),
            (40.699656, -74.069178),
            (40.699876, -74.068923),
        ],
        [
            (40.689174, -74.086005),
            (40.691266, -74.083840),
            (40.692141, -74.082934),
            (40.692548, -74.082513),
            (40.693284, -74.081755),
        ],
        [
            (40.693284, -74.081755),
            (40.693325, -74.081712),
            (40.693385, -74.081651),
        ],
    ]

    static let lindenAvenueEast: [[(Double, Double)]] = [
        [
            (40.685728, -74.078460),
            (40.686532, -74.079688),
            (40.687482, -74.081081),
            (40.688359, -74.082413),
            (40.688424, -74.082510),
            (40.688486, -74.082603),
            (40.688919, -74.083254),
        ],
        [
            (40.689813, -74.087092),
            (40.689965, -74.087222),
            (40.690152, -74.087383),
            (40.690201, -74.087429),
            (40.690432, -74.087598),
            (40.690722, -74.087825),
            (40.690770, -74.087865),
            (40.691188, -74.088165),
        ],
        [
            (40.691188, -74.088165),
            (40.691621, -74.088514),
        ],
    ]
    static let portLiberte: [(Double, Double)] = [
        (40.685776, -74.070914),
        (40.686126, -74.072483),
        (40.687903, -74.074991),
        (40.690071, -74.075853),
        (40.691242, -74.075481),
        (40.691365, -74.074935),
        (40.691454, -74.074362),
        (40.690111, -74.070644),
        (40.689428, -74.070444),
        (40.688934, -74.070362),
        (40.687991, -74.070257),
        (40.687452, -74.070199),
    ]

    static func mph(at coordinate: CLLocationCoordinate2D) -> Int? {
        if nearest(chapelAvenue, to: coordinate) <= matchMeters { return 25 }
        if nearest(cavenPointRoad, to: coordinate) <= matchMeters { return 25 }
        if nearest(lindenAvenueEast, to: coordinate) <= matchMeters { return 15 }
        if contains(portLiberte, coordinate) { return 15 }
        return nil
    }

    private static func nearest(_ roads: [[(Double, Double)]], to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        var best = CLLocationDistance.greatestFiniteMagnitude
        for road in roads {
            guard road.count >= 2 else { continue }
            for index in 1..<road.count {
                let distance = meters(
                    from: coordinate,
                    to: road[index - 1],
                    and: road[index]
                )
                if distance < best { best = distance }
            }
        }
        return best
    }

    private static func meters(
        from coordinate: CLLocationCoordinate2D,
        to start: (Double, Double),
        and end: (Double, Double)
    ) -> CLLocationDistance {
        let latScale = 111_320.0
        let lonScale = 111_320.0 * cos(coordinate.latitude * .pi / 180)
        let px = (coordinate.longitude - start.1) * lonScale
        let py = (coordinate.latitude - start.0) * latScale
        let dx = (end.1 - start.1) * lonScale
        let dy = (end.0 - start.0) * latScale
        let lengthSquared = dx * dx + dy * dy
        let t: Double
        if lengthSquared <= 0 {
            t = 0
        } else {
            t = min(1, max(0, (px * dx + py * dy) / lengthSquared))
        }
        let qx = dx * t - px
        let qy = dy * t - py
        return (qx * qx + qy * qy).squareRoot()
    }

    private static func contains(_ ring: [(Double, Double)], _ coordinate: CLLocationCoordinate2D) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var previous = ring[ring.count - 1]
        for point in ring {
            let crosses = (point.0 > coordinate.latitude) != (previous.0 > coordinate.latitude)
            if crosses {
                let x = (previous.1 - point.1) * (coordinate.latitude - point.0) / (previous.0 - point.0) + point.1
                if coordinate.longitude < x { inside.toggle() }
            }
            previous = point
        }
        return inside
    }
}
