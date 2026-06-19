import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct HealthWidgetSnapshot: Codable, Hashable {
    let metrics: [HealthWidgetMetric]
    let generatedAt: Date

    static let empty = HealthWidgetSnapshot(metrics: [], generatedAt: Date())
}

struct HealthWidgetMetric: Codable, Hashable, Identifiable {
    var id: String { title }

    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let trend: HealthWidgetTrend?

    var displayValue: String {
        unit.isEmpty ? value : "\(value) \(unit)"
    }
}

enum HealthWidgetTrend: String, Codable, Hashable {
    case negative
    case stable
    case positive

    var systemImage: String {
        switch self {
        case .negative: return "arrow.down.right"
        case .stable: return "equal"
        case .positive: return "arrow.up.right"
        }
    }
}

enum HealthWidgetStore {
    static let appGroupIdentifier: String? = "group.com.adibsouly.healthlogiq"
    static let snapshotFileName = "HealthLogiQWidgetSnapshot.json"

#if !APP_EXTENSION
    static func snapshot(from healthSnapshot: HealthSnapshot) -> HealthWidgetSnapshot {
        let preferredTitles = [
            "Steps",
            "Active Energy",
            "Sleep",
            "Body Battery"
        ]

        let orderedMetrics = healthSnapshot.metrics.filter { metric in
            preferredTitles.contains(metric.title)
        }
        .sorted { first, second in
            let firstIndex = preferredTitles.firstIndex(of: first.title) ?? preferredTitles.count
            let secondIndex = preferredTitles.firstIndex(of: second.title) ?? preferredTitles.count
            return firstIndex == secondIndex ? first.title < second.title : firstIndex < secondIndex
        }

        let metrics = orderedMetrics.map { metric in
            HealthWidgetMetric(
                title: widgetTitle(for: metric.title),
                value: metric.value,
                unit: metric.unit,
                systemImage: metric.systemImage,
                trend: widgetTrend(from: metric.trend)
            )
        }

        return HealthWidgetSnapshot(metrics: metrics, generatedAt: healthSnapshot.generatedAt)
    }
#endif

    static func save(_ snapshot: HealthWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot),
              let snapshotURL else {
            return
        }

        try? data.write(to: snapshotURL, options: [.atomic])

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "HealthLogiQMetricsWidget")
        #endif
    }

    static func load() -> HealthWidgetSnapshot {
        guard
            let snapshotURL,
            let data = try? Data(contentsOf: snapshotURL),
            let snapshot = try? JSONDecoder().decode(HealthWidgetSnapshot.self, from: data)
        else {
            return .empty
        }

        return snapshot
    }

    private static var snapshotURL: URL? {
        if let appGroupIdentifier,
           let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return containerURL.appendingPathComponent(snapshotFileName)
        }

        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(snapshotFileName)
    }

#if !APP_EXTENSION
    private static func widgetTitle(for title: String) -> String {
        title == "Active Energy" ? "Burned Calories" : title
    }

    private static func widgetTrend(from trend: HealthMetricTrend?) -> HealthWidgetTrend? {
        switch trend {
        case .below:
            return .negative
        case .near:
            return .stable
        case .above:
            return .positive
        case nil:
            return nil
        }
    }
#endif
}
