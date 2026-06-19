import SwiftUI
import WidgetKit

private struct WidgetHealthSnapshot: Codable, Hashable {
    let metrics: [WidgetHealthMetric]
    let generatedAt: Date

    static let empty = WidgetHealthSnapshot(metrics: [], generatedAt: Date())
}

private struct WidgetHealthMetric: Codable, Hashable, Identifiable {
    var id: String { title }

    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let trend: WidgetHealthTrend?

    var displayValue: String {
        unit.isEmpty ? value : "\(value) \(unit)"
    }
}

private enum WidgetHealthTrend: String, Codable, Hashable {
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

private enum WidgetHealthStore {
    static let appGroupIdentifier: String? = "group.com.adibsouly.healthlogiq"
    static let snapshotFileName = "HealthLogiQWidgetSnapshot.json"

    static func load() -> WidgetHealthSnapshot {
        guard
            let snapshotURL,
            let data = try? Data(contentsOf: snapshotURL),
            let snapshot = try? JSONDecoder().decode(WidgetHealthSnapshot.self, from: data)
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
}

private struct HealthLogiQEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetHealthSnapshot
}

private struct HealthLogiQProvider: TimelineProvider {
    func placeholder(in context: Context) -> HealthLogiQEntry {
        HealthLogiQEntry(date: Date(), snapshot: previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (HealthLogiQEntry) -> Void) {
        let snapshot = context.isPreview ? previewSnapshot : WidgetHealthStore.load()
        completion(HealthLogiQEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthLogiQEntry>) -> Void) {
        let entry = HealthLogiQEntry(date: Date(), snapshot: WidgetHealthStore.load())
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private var previewSnapshot: WidgetHealthSnapshot {
        WidgetHealthSnapshot(
            metrics: [
                WidgetHealthMetric(title: "Steps", value: "8,420", unit: "steps", systemImage: "figure.walk", trend: .positive),
                WidgetHealthMetric(title: "Burned Calories", value: "520", unit: "kcal", systemImage: "flame", trend: .positive),
                WidgetHealthMetric(title: "Sleep", value: "7.4", unit: "hr", systemImage: "bed.double.fill", trend: .positive),
                WidgetHealthMetric(title: "Body Battery", value: "82", unit: "%", systemImage: "battery.100percent", trend: .positive)
            ],
            generatedAt: Date()
        )
    }
}

private struct HealthLogiQEntryView: View {
    let entry: HealthLogiQEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if entry.snapshot.metrics.isEmpty {
                emptyState
            } else {
                switch family {
                case .systemSmall:
                    smallWidget
                case .systemMedium:
                    mediumWidget
                default:
                    largeWidget
                }
            }
        }
        .widgetURL(URL(string: "healthlogiq://dashboard"))
        .healthLogiqWidgetBackground()
        .clipped()
    }

    private var smallWidget: some View {
        let metric = entry.snapshot.metrics.first

        return VStack(alignment: .leading, spacing: 6) {
            widgetHeader

            Spacer(minLength: 2)

            if let metric {
                Image(systemName: metric.systemImage)
                    .font(.title3)
                    .foregroundStyle(.white)

                Text(metric.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(metric.value)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)

                    Text(metric.unit)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trendBadge(for: metric)
            }
        }
        .padding(12)
    }

    private var mediumWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            widgetHeader

            HStack(spacing: 6) {
                ForEach(Array(entry.snapshot.metrics.prefix(4))) { metric in
                    metricColumn(metric)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(10)
    }

    private var largeWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            widgetHeader

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(Array(entry.snapshot.metrics.prefix(4))) { metric in
                    metricRow(metric)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Spacer(minLength: 0)

            Text("Updated \(entry.snapshot.generatedAt, style: .time)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.68))
        }
        .padding(10)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            widgetHeader

            Spacer()

            Image(systemName: "heart.text.square")
                .font(.title2)
                .foregroundStyle(.white)

            Text("Open HealthLogiQ")
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text("Refresh Health data to update your widgets.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .padding(12)
    }

    private var widgetHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.circle.fill")
                .foregroundStyle(.white)

            Text("HealthLogiQ")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
    }

    private func metricColumn(_ metric: WidgetHealthMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: metric.systemImage)
                .font(.subheadline)
                .foregroundStyle(.white)

            Text(metric.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(metric.displayValue)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.62)
                .lineLimit(1)

            trendBadge(for: metric)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(6)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        .clipped()
    }

    private func metricRow(_ metric: WidgetHealthMetric) -> some View {
        HStack(spacing: 6) {
            Image(systemName: metric.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(metric.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(metric.displayValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            Spacer(minLength: 2)

            trendIcon(for: metric)
        }
        .padding(7)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        .clipped()
    }

    @ViewBuilder
    private func trendBadge(for metric: WidgetHealthMetric) -> some View {
        if let trend = metric.trend {
            HStack(spacing: 4) {
                Image(systemName: trend.systemImage)
                Text(trendLabel(for: trend))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(trendColor(for: trend).opacity(0.82), in: Capsule())
        }
    }

    @ViewBuilder
    private func trendIcon(for metric: WidgetHealthMetric) -> some View {
        if let trend = metric.trend {
            Image(systemName: trend.systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(trendColor(for: trend).opacity(0.82), in: Circle())
        }
    }

    private func trendLabel(for trend: WidgetHealthTrend) -> String {
        switch trend {
        case .negative: return "Below"
        case .stable: return "Stable"
        case .positive: return "Above"
        }
    }

    private func trendColor(for trend: WidgetHealthTrend) -> Color {
        switch trend {
        case .negative: return .orange
        case .stable: return .blue
        case .positive: return .green
        }
    }
}

struct HealthLogiQ: Widget {
    let kind = "HealthLogiQMetricsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HealthLogiQProvider()) { entry in
            HealthLogiQEntryView(entry: entry)
        }
        .configurationDisplayName("HealthLogiQ Metrics")
        .description("See your latest HealthLogiQ metrics and trends.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private extension View {
    func healthLogiqWidgetBackground() -> some View {
        modifier(HealthLogiQWidgetBackgroundModifier())
    }
}

private struct HealthLogiQWidgetBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.42, blue: 0.72), Color(red: 0.02, green: 0.66, blue: 0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                for: .widget
            )
        } else {
            content.background(
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.42, blue: 0.72), Color(red: 0.02, green: 0.66, blue: 0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

#Preview(as: .systemSmall) {
    HealthLogiQ()
} timeline: {
    HealthLogiQEntry(
        date: .now,
        snapshot: WidgetHealthSnapshot(
            metrics: [
                WidgetHealthMetric(title: "Steps", value: "8,420", unit: "steps", systemImage: "figure.walk", trend: .positive)
            ],
            generatedAt: .now
        )
    )
}
