import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

protocol HealthAgentInterpreting: AnyObject {
    var statusDescription: String { get }
    func response(to message: String, snapshot: HealthSnapshot, conversation: [ChatMessage]) async -> String
}

final class LocalHealthInterpreter: HealthAgentInterpreting {
    let statusDescription = "Rule-based insights"

    func response(to message: String, snapshot: HealthSnapshot, conversation: [ChatMessage]) async -> String {
        guard !snapshot.metrics.isEmpty else {
            return "I do not have health metrics yet. Connect Health access, then refresh so I can read today's activity, heart, sleep, and recovery signals."
        }

        let lowercasedMessage = message.lowercased()

        if asksForBaseline(lowercasedMessage) {
            return baselineResponse(to: lowercasedMessage, in: snapshot)
        }

        if lowercasedMessage.contains("sleep") {
            return focusedResponse(for: "Sleep", in: snapshot, fallback: snapshotSummary(snapshot))
        }

        if lowercasedMessage.contains("heart") || lowercasedMessage.contains("hrv") || lowercasedMessage.contains("recovery") {
            let heartMetrics = snapshot.metrics.filter { $0.title.contains("HR") || $0.title == "Activity Heart Rate" || $0.title == "HRV" }
            return metricSummary(heartMetrics, prefix: "Here is what your heart and recovery metrics show right now:")
        }

        if lowercasedMessage.contains("step") || lowercasedMessage.contains("activity") || lowercasedMessage.contains("exercise") || lowercasedMessage.contains("calorie") {
            let activityMetrics = snapshot.metrics.filter { ["Steps", "Active Energy", "Exercise", "Activity Heart Rate"].contains($0.title) }
            return metricSummary(activityMetrics, prefix: "Here is what your activity metrics show today:")
        }

        return snapshotSummary(snapshot)
    }

    private func focusedResponse(for title: String, in snapshot: HealthSnapshot, fallback: String) -> String {
        guard let metric = snapshot.metrics.first(where: { $0.title == title }) else {
            return fallback
        }

        let baseline = metric.baselineComparison.map { " Baseline comparison: \($0)" } ?? " I would compare this with your personal trend before treating it as good or bad."
        return "Your \(metric.title.lowercased()) is \(metric.value) \(metric.unit). \(metric.context)\(baseline)"
    }

    private func asksForBaseline(_ message: String) -> Bool {
        ["baseline", "compare", "normal", "range", "age", "gender", "sex"].contains { message.contains($0) }
    }

    private func baselineResponse(to message: String, in snapshot: HealthSnapshot) -> String {
        let matchingMetrics = baselineMetrics(for: message, in: snapshot)
        guard !matchingMetrics.isEmpty else {
            return "I can compare Resting HR, Sleep, Activity Heart Rate target zone, and VO2 Max when those values and your Health profile age or sex are available. Metrics like Steps, Strain, and Body Battery are better compared against your own trend for now."
        }

        let lines = matchingMetrics.map { metric in
            let unit = metric.unit.isEmpty ? "" : " \(metric.unit)"
            let baseline = metric.baselineComparison ?? "No age- or sex-adjusted baseline is available for this metric yet."
            return "- \(metric.title): \(metric.value)\(unit). \(baseline)"
        }

        return (["Using your Health profile (\(snapshot.profile.description)):"] + lines + ["Use these as general reference ranges, not a diagnosis. Your own multi-day trend still matters most."]).joined(separator: "\n")
    }

    private func baselineMetrics(for message: String, in snapshot: HealthSnapshot) -> [HealthMetric] {
        let candidates = snapshot.metrics.filter { $0.baselineComparison != nil }

        if message.contains("vo2") || message.contains("cardio") {
            return candidates.filter { $0.title == "VO2 Max" }
        }

        if message.contains("sleep") {
            return candidates.filter { $0.title == "Sleep" }
        }

        if message.contains("resting") {
            return candidates.filter { $0.title == "Resting HR" }
        }

        if message.contains("heart") || message.contains("hr") {
            return candidates.filter { $0.title == "Resting HR" || $0.title == "Activity Heart Rate" }
        }

        return candidates
    }

    private func snapshotSummary(_ snapshot: HealthSnapshot) -> String {
        let strongestSignals = snapshot.metrics.prefix(5)
        return metricSummary(Array(strongestSignals), prefix: "Here is the latest read from Apple Health:")
    }

    private func metricSummary(_ metrics: [HealthMetric], prefix: String) -> String {
        guard !metrics.isEmpty else {
            return "I could not find that metric in the current Health snapshot. Try refreshing Health access or ask about steps, exercise, heart rate, HRV, or sleep."
        }

        let lines = metrics.map { metric in
            let unit = metric.unit.isEmpty ? "" : " \(metric.unit)"
            return "- \(metric.title): \(metric.value)\(unit)"
        }

        return ([prefix] + lines + ["I can interpret trends better once we add baseline comparison across multiple days."]).joined(separator: "\n")
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
final class FoundationModelHealthInterpreter: HealthAgentInterpreting {
    private let model = SystemLanguageModel.default
    private var session: LanguageModelSession?

    var statusDescription: String {
        switch model.availability {
        case .available:
            return "On-device AI"
        case .unavailable(.deviceNotEligible):
            return "Apple Intelligence unavailable"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence off"
        case .unavailable(.modelNotReady):
            return "AI model downloading"
        case .unavailable:
            return "AI unavailable"
        }
    }

    func response(to message: String, snapshot: HealthSnapshot, conversation: [ChatMessage]) async -> String {
        guard case .available = model.availability else {
            return await LocalHealthInterpreter().response(to: message, snapshot: snapshot, conversation: conversation)
        }

        do {
            if session == nil {
                session = LanguageModelSession(instructions: instructions)
            }

            guard let session else {
                return await LocalHealthInterpreter().response(to: message, snapshot: snapshot, conversation: conversation)
            }

            let recentConversation = conversation.suffix(6).map { message in
                "\(message.role.label): \(message.text)"
            }.joined(separator: "\n")

            let prompt = """
            Current Apple Health snapshot:
            \(snapshot.agentContext)

            Recent chat:
            \(recentConversation)

            User question:
            \(message)
            """

            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            return await LocalHealthInterpreter().response(to: message, snapshot: snapshot, conversation: conversation)
        }
    }

    private var instructions: String {
        """
        You are a private health insights agent inside an iPhone app. Interpret Apple Health metrics in plain language.
        Use the provided baseline comparison text when the user asks whether a metric is normal or how it compares by age or sex.
        Be specific about what the current metrics suggest, ask for missing baseline context when needed, and do not diagnose disease.
        Recommend urgent medical care only for severe or alarming symptoms the user explicitly reports.
        Keep replies concise and useful for a mobile chat.
        """
    }
}
#endif

final class HealthInterpreterFactory {
    static func makeInterpreter() -> HealthAgentInterpreting {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return FoundationModelHealthInterpreter()
        }
        #endif

        return LocalHealthInterpreter()
    }
}
