import Foundation
import HealthKit

struct HealthMetric: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let value: String
    let unit: String
    let context: String
    let systemImage: String
    let baselineComparison: String?
    let baselineReference: HealthMetricBaseline?
    let trend: HealthMetricTrend?

    init(
        title: String,
        value: String,
        unit: String,
        context: String,
        systemImage: String,
        baselineComparison: String? = nil,
        baselineReference: HealthMetricBaseline? = nil,
        trend: HealthMetricTrend? = nil
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.context = context
        self.systemImage = systemImage
        self.baselineComparison = baselineComparison
        self.baselineReference = baselineReference
        self.trend = trend
    }
}

enum HealthMetricTrend: Hashable {
    case below(referenceValue: Double)
    case near(referenceValue: Double)
    case above(referenceValue: Double)

    var referenceValue: Double {
        switch self {
        case .below(let referenceValue),
             .near(let referenceValue),
             .above(let referenceValue):
            return referenceValue
        }
    }
}

struct HealthMetricBaseline: Hashable {
    let lowerBound: Double
    let upperBound: Double?
    let label: String
    let source: String

    var isRange: Bool {
        upperBound != nil
    }
}

struct HealthProfile: Hashable {
    let age: Int?
    let biologicalSex: HKBiologicalSex

    var description: String {
        let ageText = age.map { "age \($0)" } ?? "age not available"
        return "\(ageText), \(sexDescription)"
    }

    var sexDescription: String {
        switch biologicalSex {
        case .female: return "female"
        case .male: return "male"
        case .other: return "other sex"
        case .notSet: return "sex not set"
        @unknown default: return "sex not set"
        }
    }
}

struct HealthSnapshot {
    let metrics: [HealthMetric]
    let generatedAt: Date
    let profile: HealthProfile

    var isEmpty: Bool {
        metrics.isEmpty
    }

    var agentContext: String {
        guard !metrics.isEmpty else {
            return "No HealthKit metrics are available yet."
        }

        return metrics
            .map { metric in
                let baseline = metric.baselineComparison.map { " Baseline: \($0)" } ?? ""
                return "\(metric.title): \(metric.value) \(metric.unit). \(metric.context)\(baseline)"
            }
            .joined(separator: "\n")
    }
}

struct HealthMetricSample: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let value: Double
}

enum HealthHistoryRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case threeMonths = "3 Months"
    case sixMonths = "6 Months"
    case year = "Year"

    var id: String { rawValue }

    func startDate(from date: Date, calendar: Calendar) -> Date {
        switch self {
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: date) ?? date
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: date) ?? date
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: date) ?? date
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: date) ?? date
        case .year:
            return calendar.date(byAdding: .year, value: -1, to: date) ?? date
        }
    }

    var intervalComponents: DateComponents {
        DateComponents(day: 1)
    }
}

final class HealthKitManager {
    private let healthStore = HKHealthStore()
    private let calendar = Calendar.current

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.vo2Max),
            HKWorkoutType.workoutType()
        ]

        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }

        if let dateOfBirthType = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            types.insert(dateOfBirthType)
        }

        if let biologicalSexType = HKObjectType.characteristicType(forIdentifier: .biologicalSex) {
            types.insert(biologicalSexType)
        }

        return types
    }

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else {
            throw HealthKitError.healthDataUnavailable
        }

        guard Bundle.main.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") != nil else {
            throw HealthKitError.missingHealthShareUsageDescription
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    func fetchSnapshot() async throws -> HealthSnapshot {
        let profile = healthProfile()

        async let steps = cumulativeMetric(
            title: "Steps",
            type: HKQuantityType(.stepCount),
            unit: .count(),
            systemImage: "figure.walk",
            context: "Total steps recorded today."
        )

        async let activeEnergy = cumulativeMetric(
            title: "Active Energy",
            type: HKQuantityType(.activeEnergyBurned),
            unit: .kilocalorie(),
            systemImage: "flame",
            context: "Active calories recorded today."
        )

        async let exercise = cumulativeMetric(
            title: "Exercise",
            type: HKQuantityType(.appleExerciseTime),
            unit: .minute(),
            systemImage: "figure.run",
            context: "Exercise minutes recorded today."
        )

        async let heartRate = exerciseHeartRateMetric()

        async let restingHeartRate = latestMetric(
            title: "Resting HR",
            type: HKQuantityType(.restingHeartRate),
            unit: HKUnit.count().unitDivided(by: .minute()),
            systemImage: "heart.text.square",
            context: "Most recent resting heart rate sample."
        )

        async let hrv = latestMetric(
            title: "HRV",
            type: HKQuantityType(.heartRateVariabilitySDNN),
            unit: .secondUnit(with: .milli),
            systemImage: "waveform.path.ecg",
            context: "Most recent heart rate variability SDNN sample."
        )

        async let vo2Max = latestMetric(
            title: "VO2 Max",
            type: HKQuantityType(.vo2Max),
            unit: vo2MaxUnit,
            systemImage: "lungs",
            context: "Most recent cardio fitness estimate from Apple Health."
        )

        async let sleep = sleepMetric()

        let values = try await [
            steps,
            activeEnergy,
            exercise,
            heartRate,
            restingHeartRate,
            hrv,
            vo2Max,
            sleep
        ]

        var metrics = values.compactMap { $0 }
        metrics.append(contentsOf: derivedMetrics(from: metrics))
        var enrichedMetrics: [HealthMetric] = []
        for metric in metrics {
            let enrichedMetric = HealthMetric(
                title: metric.title,
                value: metric.value,
                unit: metric.unit,
                context: metric.context,
                systemImage: metric.systemImage,
                baselineComparison: baselineComparison(for: metric, profile: profile),
                baselineReference: baselineReference(for: metric, profile: profile),
                trend: await trend(for: metric)
            )
            enrichedMetrics.append(enrichedMetric)
        }
        metrics = enrichedMetrics

        return HealthSnapshot(metrics: metrics, generatedAt: Date(), profile: profile)
    }

    func fetchHistory(for metric: HealthMetric, range: HealthHistoryRange) async throws -> [HealthMetricSample] {
        switch metric.title {
        case "Steps":
            return try await quantityHistory(type: HKQuantityType(.stepCount), unit: .count(), options: .cumulativeSum, range: range)
        case "Active Energy":
            return try await quantityHistory(type: HKQuantityType(.activeEnergyBurned), unit: .kilocalorie(), options: .cumulativeSum, range: range)
        case "Exercise":
            return try await quantityHistory(type: HKQuantityType(.appleExerciseTime), unit: .minute(), options: .cumulativeSum, range: range)
        case "Activity Heart Rate":
            return try await exerciseHeartRateHistory(range: range)
        case "Resting HR":
            return try await quantityHistory(type: HKQuantityType(.restingHeartRate), unit: HKUnit.count().unitDivided(by: .minute()), options: .discreteAverage, range: range)
        case "HRV":
            return try await quantityHistory(type: HKQuantityType(.heartRateVariabilitySDNN), unit: .secondUnit(with: .milli), options: .discreteAverage, range: range)
        case "VO2 Max":
            return try await quantityHistory(type: HKQuantityType(.vo2Max), unit: vo2MaxUnit, options: .discreteAverage, range: range)
        case "Sleep":
            return try await sleepHistory(range: range)
        case "Body Battery":
            return try await bodyBatteryHistory(range: range)
        case "Strain":
            return try await strainHistory(range: range)
        case "Stress":
            return try await stressHistory(range: range)
        default:
            return []
        }
    }

    private func trend(for metric: HealthMetric) async -> HealthMetricTrend? {
        guard let currentValue = numericValue(metric.value), currentValue > 0 else {
            return nil
        }

        guard let history = try? await fetchHistory(for: metric, range: .month) else {
            return nil
        }

        let values = history
            .map(\.value)
            .filter { $0.isFinite && $0 > 0 }
            .sorted()
        guard values.count >= 2 else {
            return nil
        }

        let reference = median(of: values)
        let threshold = max(abs(reference) * 0.03, 0.1)
        if currentValue < reference - threshold {
            return lowerIsBetter(metric.title) ? .above(referenceValue: reference) : .below(referenceValue: reference)
        }
        if currentValue > reference + threshold {
            return lowerIsBetter(metric.title) ? .below(referenceValue: reference) : .above(referenceValue: reference)
        }
        return .near(referenceValue: reference)
    }

    private func lowerIsBetter(_ metricTitle: String) -> Bool {
        ["Resting HR", "Strain", "Stress"].contains(metricTitle)
    }

    private func median(of values: [Double]) -> Double {
        let midpoint = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[midpoint - 1] + values[midpoint]) / 2
        }
        return values[midpoint]
    }

    private func quantityHistory(
        type: HKQuantityType,
        unit: HKUnit,
        options: HKStatisticsOptions,
        range: HealthHistoryRange
    ) async throws -> [HealthMetricSample] {
        let endDate = Date()
        let startDate = range.startDate(from: endDate, calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let samplePredicate = HKSamplePredicate.quantitySample(type: type, predicate: predicate)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: samplePredicate,
            options: options,
            anchorDate: calendar.startOfDay(for: startDate),
            intervalComponents: range.intervalComponents
        )

        let collection = try await descriptor.result(for: healthStore)
        var samples: [HealthMetricSample] = []
        collection.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
            let quantity: HKQuantity?
            if options.contains(.cumulativeSum) {
                quantity = statistics.sumQuantity()
            } else {
                quantity = statistics.averageQuantity()
            }

            if let value = quantity?.doubleValue(for: unit), value > 0 {
                samples.append(HealthMetricSample(date: statistics.startDate, value: value))
            }
        }

        return samples
    }

    private func exerciseHeartRateHistory(range: HealthHistoryRange) async throws -> [HealthMetricSample] {
        let endDate = Date()
        let startDate = range.startDate(from: endDate, calendar: calendar)
        let workouts = try await workouts(from: startDate, to: endDate)
        var weightedTotals: [Date: Double] = [:]
        var durations: [Date: TimeInterval] = [:]

        for workout in workouts {
            let intervalStart = max(workout.startDate, startDate)
            let intervalEnd = min(workout.endDate, endDate)
            let duration = intervalEnd.timeIntervalSince(intervalStart)
            guard duration > 0,
                  let averageHeartRate = try await averageHeartRate(from: intervalStart, to: intervalEnd) else {
                continue
            }

            let bucketDate = bucketStart(for: workout.startDate, range: range)
            weightedTotals[bucketDate, default: 0] += averageHeartRate * duration
            durations[bucketDate, default: 0] += duration
        }

        return weightedTotals.compactMap { date, total in
            guard let duration = durations[date], duration > 0 else { return nil }
            return HealthMetricSample(date: date, value: total / duration)
        }
        .sorted { $0.date < $1.date }
    }

    private func sleepHistory(range: HealthHistoryRange) async throws -> [HealthMetricSample] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }

        let endDate = Date()
        let startDate = range.startDate(from: endDate, calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]

        var buckets: [Date: TimeInterval] = [:]
        let samples = try await descriptor.result(for: healthStore)
        for sample in samples where asleepValues.contains(sample.value) {
            let bucketDate = bucketStart(for: sample.startDate, range: range)
            buckets[bucketDate, default: 0] += sample.endDate.timeIntervalSince(sample.startDate)
        }

        return buckets
            .map { HealthMetricSample(date: $0.key, value: $0.value / 3600) }
            .sorted { $0.date < $1.date }
    }

    private func bodyBatteryHistory(range: HealthHistoryRange) async throws -> [HealthMetricSample] {
        async let sleep = sleepHistory(range: range)
        async let hrv = quantityHistory(type: HKQuantityType(.heartRateVariabilitySDNN), unit: .secondUnit(with: .milli), options: .discreteAverage, range: range)
        async let restingHeartRate = quantityHistory(type: HKQuantityType(.restingHeartRate), unit: HKUnit.count().unitDivided(by: .minute()), options: .discreteAverage, range: range)

        return try await combinedHistory(range: range, series: [sleep, hrv, restingHeartRate]) { values in
            bodyBatteryScore(sleepHours: values[0], hrv: values[1], restingHeartRate: values[2])
        }
    }

    private func strainHistory(range: HealthHistoryRange) async throws -> [HealthMetricSample] {
        async let steps = quantityHistory(type: HKQuantityType(.stepCount), unit: .count(), options: .cumulativeSum, range: range)
        async let exercise = quantityHistory(type: HKQuantityType(.appleExerciseTime), unit: .minute(), options: .cumulativeSum, range: range)
        async let activeEnergy = quantityHistory(type: HKQuantityType(.activeEnergyBurned), unit: .kilocalorie(), options: .cumulativeSum, range: range)
        async let heartRate = quantityHistory(type: HKQuantityType(.heartRate), unit: HKUnit.count().unitDivided(by: .minute()), options: .discreteAverage, range: range)

        return try await combinedHistory(range: range, series: [steps, exercise, activeEnergy, heartRate]) { values in
            strainScore(steps: values[0], exerciseMinutes: values[1], activeEnergy: values[2], heartRate: values[3])
        }
    }

    private func stressHistory(range: HealthHistoryRange) async throws -> [HealthMetricSample] {
        async let sleep = sleepHistory(range: range)
        async let hrv = quantityHistory(type: HKQuantityType(.heartRateVariabilitySDNN), unit: .secondUnit(with: .milli), options: .discreteAverage, range: range)
        async let restingHeartRate = quantityHistory(type: HKQuantityType(.restingHeartRate), unit: HKUnit.count().unitDivided(by: .minute()), options: .discreteAverage, range: range)
        async let strain = strainHistory(range: range)

        return try await combinedHistory(range: range, series: [sleep, hrv, restingHeartRate, strain]) { values in
            stressScore(sleepHours: values[0], hrv: values[1], restingHeartRate: values[2], strain: values[3])
        }
    }

    private func combinedHistory(
        range: HealthHistoryRange,
        series: [[HealthMetricSample]],
        score: ([Double?]) -> Double?
    ) -> [HealthMetricSample] {
        let keyedSeries = series.map { samples in
            Dictionary(uniqueKeysWithValues: samples.map { (bucketStart(for: $0.date, range: range), $0.value) })
        }
        let dates = Set(keyedSeries.flatMap { $0.keys }).sorted()

        return dates.compactMap { date in
            let values = keyedSeries.map { $0[date] }
            guard let value = score(values) else { return nil }
            return HealthMetricSample(date: date, value: value)
        }
    }

    private func bucketStart(for date: Date, range: HealthHistoryRange) -> Date {
        calendar.startOfDay(for: date)
    }

    private func cumulativeMetric(
        title: String,
        type: HKQuantityType,
        unit: HKUnit,
        systemImage: String,
        context: String
    ) async throws -> HealthMetric? {
        let predicate = HKQuery.predicateForSamples(withStart: startOfToday, end: Date())
        let samplePredicate = HKSamplePredicate.quantitySample(type: type, predicate: predicate)
        let descriptor = HKStatisticsQueryDescriptor(predicate: samplePredicate, options: .cumulativeSum)
        let value = try await descriptor.result(for: healthStore)?.sumQuantity()?.doubleValue(for: unit)

        return metric(title: title, value: value, unit: displayUnit(for: unit), systemImage: systemImage, context: context)
    }

    private func exerciseHeartRateMetric() async throws -> HealthMetric? {
        let endDate = Date()
        let workouts = try await workouts(from: startOfToday, to: endDate)
        var weightedTotal = 0.0
        var totalDuration: TimeInterval = 0

        for workout in workouts {
            let intervalStart = max(workout.startDate, startOfToday)
            let intervalEnd = min(workout.endDate, endDate)
            let duration = intervalEnd.timeIntervalSince(intervalStart)
            guard duration > 0,
                  let averageHeartRate = try await averageHeartRate(from: intervalStart, to: intervalEnd) else {
                continue
            }

            weightedTotal += averageHeartRate * duration
            totalDuration += duration
        }

        guard totalDuration > 0 else {
            return nil
        }

        return HealthMetric(
            title: "Activity Heart Rate",
            value: formatted(weightedTotal / totalDuration),
            unit: "bpm",
            context: "Average heart rate during today's workouts up to now.",
            systemImage: "heart"
        )
    }

    private func workouts(from startDate: Date, to endDate: Date) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )

        return try await descriptor.result(for: healthStore)
    }

    private func averageHeartRate(from startDate: Date, to endDate: Date) async throws -> Double? {
        let unit = HKUnit.count().unitDivided(by: .minute())
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let samplePredicate = HKSamplePredicate.quantitySample(type: HKQuantityType(.heartRate), predicate: predicate)
        let descriptor = HKStatisticsQueryDescriptor(predicate: samplePredicate, options: .discreteAverage)

        return try await descriptor.result(for: healthStore)?.averageQuantity()?.doubleValue(for: unit)
    }

    private func latestMetric(
        title: String,
        type: HKQuantityType,
        unit: HKUnit,
        systemImage: String,
        context: String
    ) async throws -> HealthMetric? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        let sample = try await descriptor.result(for: healthStore).first
        let value = sample?.quantity.doubleValue(for: unit)

        return metric(title: title, value: value, unit: displayUnit(for: unit), systemImage: systemImage, context: context)
    }

    private func sleepMetric() async throws -> HealthMetric? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: calendar.date(byAdding: .day, value: -1, to: Date()), end: Date())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 30
        )

        let samples = try await descriptor.result(for: healthStore)
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        let seconds = samples
            .filter { asleepValues.contains($0.value) }
            .reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

        guard seconds > 0 else {
            return nil
        }

        return HealthMetric(
            title: "Sleep",
            value: formatted(seconds / 3600),
            unit: "hr",
            context: "Estimated sleep duration from the last 24 hours.",
            systemImage: "bed.double"
        )
    }

    private func derivedMetrics(from metrics: [HealthMetric]) -> [HealthMetric] {
        var derivedMetrics: [HealthMetric] = []

        if let bodyBattery = bodyBatteryMetric(from: metrics) {
            derivedMetrics.append(bodyBattery)
        }

        if let strain = strainMetric(from: metrics) {
            derivedMetrics.append(strain)
        }

        if let stress = stressMetric(from: metrics + derivedMetrics) {
            derivedMetrics.append(stress)
        }

        return derivedMetrics
    }

    private func bodyBatteryMetric(from metrics: [HealthMetric]) -> HealthMetric? {
        let sleepHours = metricValue("Sleep", in: metrics)
        let hrv = metricValue("HRV", in: metrics)
        let restingHeartRate = metricValue("Resting HR", in: metrics)

        guard sleepHours != nil || hrv != nil || restingHeartRate != nil else {
            return nil
        }

        guard let clampedScore = bodyBatteryScore(sleepHours: sleepHours, hrv: hrv, restingHeartRate: restingHeartRate) else {
            return nil
        }

        return HealthMetric(
            title: "Body Battery",
            value: formatted(clampedScore),
            unit: "%",
            context: "Estimated energy score from sleep, HRV, and resting heart rate.",
            systemImage: "battery.75percent"
        )
    }

    private func strainMetric(from metrics: [HealthMetric]) -> HealthMetric? {
        let steps = metricValue("Steps", in: metrics)
        let exerciseMinutes = metricValue("Exercise", in: metrics)
        let activeEnergy = metricValue("Active Energy", in: metrics)
        let heartRate = metricValue("Activity Heart Rate", in: metrics)

        guard steps != nil || exerciseMinutes != nil || activeEnergy != nil || heartRate != nil else {
            return nil
        }

        guard let clampedScore = strainScore(steps: steps, exerciseMinutes: exerciseMinutes, activeEnergy: activeEnergy, heartRate: heartRate) else {
            return nil
        }

        return HealthMetric(
            title: "Strain",
            value: formatted(clampedScore),
            unit: "%",
            context: "Estimated daily load percentage from movement, exercise, calories, and heart rate.",
            systemImage: "bolt.heart"
        )
    }

    private func stressMetric(from metrics: [HealthMetric]) -> HealthMetric? {
        let sleepHours = metricValue("Sleep", in: metrics)
        let hrv = metricValue("HRV", in: metrics)
        let restingHeartRate = metricValue("Resting HR", in: metrics)
        let strain = metricValue("Strain", in: metrics)

        guard sleepHours != nil || hrv != nil || restingHeartRate != nil || strain != nil else {
            return nil
        }

        guard let clampedScore = stressScore(sleepHours: sleepHours, hrv: hrv, restingHeartRate: restingHeartRate, strain: strain) else {
            return nil
        }

        return HealthMetric(
            title: "Stress",
            value: formatted(clampedScore),
            unit: "%",
            context: "Estimated stress load from HRV, resting heart rate, sleep, and strain.",
            systemImage: "brain.head.profile"
        )
    }

    private func bodyBatteryScore(sleepHours: Double?, hrv: Double?, restingHeartRate: Double?) -> Double? {
        var weightedScore = 0.0
        var availableWeight = 0.0

        if let sleepHours {
            weightedScore += min(sleepHours / 8.0, 1.0) * 45.0
            availableWeight += 45.0
        }

        if let hrv {
            weightedScore += min(hrv / 80.0, 1.0) * 30.0
            availableWeight += 30.0
        }

        if let restingHeartRate {
            let heartRateScore = 1.0 - min(max(restingHeartRate - 45.0, 0.0) / 45.0, 1.0)
            weightedScore += heartRateScore * 25.0
            availableWeight += 25.0
        }

        guard availableWeight > 0 else {
            return nil
        }

        return min(max((weightedScore / availableWeight) * 100.0, 0.0), 100.0)
    }

    private func strainScore(steps: Double?, exerciseMinutes: Double?, activeEnergy: Double?, heartRate: Double?) -> Double? {
        var weightedScore = 0.0
        var availableWeight = 0.0

        if let steps {
            weightedScore += min(steps / 12_000.0, 1.0) * 5.0
            availableWeight += 5.0
        }

        if let exerciseMinutes {
            weightedScore += min(exerciseMinutes / 60.0, 1.0) * 7.0
            availableWeight += 7.0
        }

        if let activeEnergy {
            weightedScore += min(activeEnergy / 800.0, 1.0) * 5.0
            availableWeight += 5.0
        }

        if let heartRate {
            weightedScore += min(max(heartRate - 70.0, 0.0) / 70.0, 1.0) * 4.0
            availableWeight += 4.0
        }

        guard availableWeight > 0 else {
            return nil
        }

        return min(max((weightedScore / availableWeight) * 100.0, 0.0), 100.0)
    }

    private func stressScore(sleepHours: Double?, hrv: Double?, restingHeartRate: Double?, strain: Double?) -> Double? {
        var weightedScore = 0.0
        var availableWeight = 0.0

        if let hrv {
            let hrvStress = 1.0 - min(hrv / 80.0, 1.0)
            weightedScore += hrvStress * 35.0
            availableWeight += 35.0
        }

        if let restingHeartRate {
            let heartRateStress = min(max(restingHeartRate - 50.0, 0.0) / 40.0, 1.0)
            weightedScore += heartRateStress * 30.0
            availableWeight += 30.0
        }

        if let sleepHours {
            let sleepStress = 1.0 - min(sleepHours / 8.0, 1.0)
            weightedScore += sleepStress * 20.0
            availableWeight += 20.0
        }

        if let strain {
            weightedScore += min(max(strain, 0.0) / 100.0, 1.0) * 15.0
            availableWeight += 15.0
        }

        guard availableWeight > 0 else {
            return nil
        }

        return min(max((weightedScore / availableWeight) * 100.0, 0.0), 100.0)
    }

    private func metricValue(_ title: String, in metrics: [HealthMetric]) -> Double? {
        guard let metric = metrics.first(where: { $0.title == title }) else {
            return nil
        }

        let normalizedValue = metric.value.replacingOccurrences(of: ",", with: "")
        return Double(normalizedValue)
    }

    private func healthProfile() -> HealthProfile {
        let age: Int?
        if let birthComponents = try? healthStore.dateOfBirthComponents(), let birthYear = birthComponents.year {
            let currentYear = calendar.component(.year, from: Date())
            age = max(currentYear - birthYear, 0)
        } else {
            age = nil
        }

        let biologicalSex = (try? healthStore.biologicalSex().biologicalSex) ?? .notSet
        return HealthProfile(age: age, biologicalSex: biologicalSex)
    }

    private func baselineComparison(for metric: HealthMetric, profile: HealthProfile) -> String? {
        guard let value = numericValue(metric.value) else { return nil }

        switch metric.title {
        case "Resting HR":
            guard let range = restingHeartRateRange(for: profile.age) else { return nil }
            return comparisonText(
                value: value,
                low: range.low,
                high: range.high,
                unit: "bpm",
                source: "Cleveland Clinic resting heart rate range for this age group"
            )
        case "Activity Heart Rate":
            guard let age = profile.age else {
                return "Add date of birth in Health to compare exercise heart rate against an age-based target zone."
            }
            let maximumHeartRate = max(220 - age, 0)
            let low = Double(maximumHeartRate) * 0.60
            let high = Double(maximumHeartRate) * 0.85
            return comparisonText(
                value: value,
                low: low,
                high: high,
                unit: "bpm",
                source: "Cleveland Clinic age-predicted exercise target zone"
            )
        case "Sleep":
            guard let range = sleepRange(for: profile.age) else { return nil }
            return comparisonText(
                value: value,
                low: range.low,
                high: range.high,
                unit: "hr",
                source: "Cleveland Clinic sleep duration range for this age group"
            )
        case "VO2 Max":
            return vo2MaxBaseline(value: value, profile: profile)
        default:
            return nil
        }
    }

    private func baselineReference(for metric: HealthMetric, profile: HealthProfile) -> HealthMetricBaseline? {
        switch metric.title {
        case "Resting HR":
            guard let range = restingHeartRateRange(for: profile.age) else { return nil }
            return HealthMetricBaseline(
                lowerBound: range.low,
                upperBound: range.high,
                label: "Baseline",
                source: "Cleveland Clinic age-group resting heart rate"
            )
        case "Activity Heart Rate":
            guard let age = profile.age else { return nil }
            let maximumHeartRate = max(220 - age, 0)
            return HealthMetricBaseline(
                lowerBound: Double(maximumHeartRate) * 0.60,
                upperBound: Double(maximumHeartRate) * 0.85,
                label: "Target zone",
                source: "Cleveland Clinic age-predicted exercise target zone"
            )
        case "Sleep":
            guard let range = sleepRange(for: profile.age) else { return nil }
            return HealthMetricBaseline(
                lowerBound: range.low,
                upperBound: range.high,
                label: "Baseline",
                source: "Cleveland Clinic age-group sleep duration"
            )
        case "VO2 Max":
            guard let age = profile.age,
                  let threshold = vo2MaxGoodThreshold(age: age, biologicalSex: profile.biologicalSex) else {
                return nil
            }
            return HealthMetricBaseline(
                lowerBound: threshold,
                upperBound: nil,
                label: "Good baseline",
                source: "Cleveland Clinic age- and sex-adjusted VO2 Max context"
            )
        default:
            return nil
        }
    }

    private func restingHeartRateRange(for age: Int?) -> (low: Double, high: Double)? {
        guard let age else { return (60, 100) }
        switch age {
        case 0: return (100, 205)
        case 1...2: return (98, 140)
        case 3...4: return (80, 120)
        case 5...12: return (75, 118)
        default: return (60, 100)
        }
    }

    private func sleepRange(for age: Int?) -> (low: Double, high: Double)? {
        guard let age else { return nil }
        switch age {
        case 0: return (14, 17)
        case 1...5: return (10, 14)
        case 6...12: return (9, 12)
        case 13...18: return (8, 10)
        default: return (7, 9)
        }
    }

    private func vo2MaxBaseline(value: Double, profile: HealthProfile) -> String {
        guard let age = profile.age else {
            return "Add date of birth in Health to compare VO2 Max by age. Cleveland Clinic notes VO2 Max should be interpreted by age and sex."
        }

        guard let goodThreshold = vo2MaxGoodThreshold(age: age, biologicalSex: profile.biologicalSex) else {
            return "Cleveland Clinic notes VO2 Max should be interpreted by age and sex; sex is not set in Health, so use your personal trend for now."
        }

        let status = value >= goodThreshold ? "at or above" : "below"
        return "\(formatted(value)) ml/kg/min is \(status) an age- and sex-adjusted good-fitness reference of about \(formatted(goodThreshold)) ml/kg/min. Cleveland Clinic notes VO2 Max naturally declines with age and differs by sex."
    }

    private func vo2MaxGoodThreshold(age: Int, biologicalSex: HKBiologicalSex) -> Double? {
        let thresholds: [ClosedRange<Int>: (male: Double, female: Double)] = [
            18...29: (45.4, 39.5),
            30...39: (44.0, 37.8),
            40...49: (42.4, 36.3),
            50...59: (39.2, 33.0),
            60...69: (35.5, 30.0),
            70...120: (32.0, 27.0)
        ]

        guard let match = thresholds.first(where: { $0.key.contains(age) })?.value else {
            return nil
        }

        switch biologicalSex {
        case .male: return match.male
        case .female: return match.female
        default: return nil
        }
    }

    private func comparisonText(value: Double, low: Double, high: Double, unit: String, source: String) -> String {
        let status: String
        if value < low {
            status = "below"
        } else if value > high {
            status = "above"
        } else {
            status = "within"
        }

        return "\(formatted(value)) \(unit) is \(status) the \(formatted(low))-\(formatted(high)) \(unit) reference. Source: \(source)."
    }

    private func numericValue(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: ""))
    }

    private var startOfToday: Date {
        calendar.startOfDay(for: Date())
    }

    private var vo2MaxUnit: HKUnit {
        HKUnit.literUnit(with: .milli)
            .unitDivided(by: .gramUnit(with: .kilo))
            .unitDivided(by: .minute())
    }

    private func metric(
        title: String,
        value: Double?,
        unit: String,
        systemImage: String,
        context: String
    ) -> HealthMetric? {
        guard let value, value > 0 else {
            return nil
        }

        return HealthMetric(
            title: title,
            value: formatted(value),
            unit: unit,
            context: context,
            systemImage: systemImage
        )
    }

    private func formatted(_ value: Double) -> String {
        if value >= 100 || value.rounded() == value {
            return value.formatted(.number.precision(.fractionLength(0)))
        }

        return value.formatted(.number.precision(.fractionLength(1)))
    }

    private func displayUnit(for unit: HKUnit) -> String {
        if unit == vo2MaxUnit {
            return "ml/kg/min"
        }

        switch unit {
        case .count():
            return ""
        case .kilocalorie():
            return "kcal"
        case .minute():
            return "min"
        case .secondUnit(with: .milli):
            return "ms"
        default:
            return "bpm"
        }
    }
}

enum HealthKitError: LocalizedError {
    case healthDataUnavailable
    case missingHealthShareUsageDescription

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "Health data is not available on this device."
        case .missingHealthShareUsageDescription:
            return "Add NSHealthShareUsageDescription to the app target's Info.plist before requesting Apple Health access."
        }
    }
}
