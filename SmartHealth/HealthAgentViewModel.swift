import Combine
import Foundation
import HealthKit

struct ChatMessage: Identifiable, Hashable {
    enum Role: Hashable {
        case assistant
        case user

        var label: String {
            switch self {
            case .assistant:
                return "Assistant"
            case .user:
                return "User"
            }
        }
    }

    let id = UUID()
    let role: Role
    let text: String
    let createdAt: Date
}

@MainActor
final class HealthAgentViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = [
        ChatMessage(
            role: .assistant,
            text: "I can read your Apple Health metrics and help interpret activity, heart, recovery, and sleep patterns. Connect Health access to begin.",
            createdAt: Date()
        )
    ]
    @Published var currentInput = ""
    @Published var snapshot = HealthSnapshot(metrics: [], generatedAt: Date(), profile: HealthProfile(age: nil, biologicalSex: .notSet))
    @Published var isLoadingHealthData = false
    @Published var isSendingMessage = false
    @Published var hasAttemptedHealthConnection = false
    @Published var hasCompletedHealthAuthorization = false
    @Published var errorMessage: String?

    private let healthKitManager = HealthKitManager()
    private let interpreter: HealthAgentInterpreting = HealthInterpreterFactory.makeInterpreter()
    private let maxRetainedMessages = 30

    var metricCards: [HealthMetric] {
        snapshot.metrics
    }

    var agentStatus: String {
        interpreter.statusDescription
    }

    var canSend: Bool {
        !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSendingMessage
    }

    func connectHealth() async {
        isLoadingHealthData = true
        hasAttemptedHealthConnection = true
        errorMessage = nil
        defer { isLoadingHealthData = false }

        do {
            try await healthKitManager.requestAuthorization()
            hasCompletedHealthAuthorization = true
            try await refreshHealthData()
        } catch {
            hasCompletedHealthAuthorization = false
            errorMessage = error.localizedDescription
            appendAssistantMessage("I could not access Health data: \(error.localizedDescription)")
        }
    }

    func refreshHealthData() async throws {
        let updatedSnapshot = try await healthKitManager.fetchSnapshot()
        hasCompletedHealthAuthorization = true
        snapshot = updatedSnapshot
        HealthWidgetStore.save(HealthWidgetStore.snapshot(from: updatedSnapshot))

        if updatedSnapshot.isEmpty {
            appendAssistantMessage("Health access is connected, but I did not find recent metrics yet. Apple Health may not have data for the requested categories, or some categories may still be disabled.")
        } else {
            appendAssistantMessage(openingInsight(for: updatedSnapshot))
        }
    }

    func refreshFromButton() async {
        isLoadingHealthData = true
        errorMessage = nil
        defer { isLoadingHealthData = false }

        do {
            try await refreshHealthData()
        } catch {
            errorMessage = error.localizedDescription
            appendAssistantMessage("I could not refresh Health data: \(error.localizedDescription)")
        }
    }

    func sendMessage() async {
        let trimmedMessage = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty, !isSendingMessage else {
            return
        }

        currentInput = ""
        isSendingMessage = true
        appendUserMessage(trimmedMessage)
        defer { isSendingMessage = false }

        let reply = await interpreter.response(to: trimmedMessage, snapshot: snapshot, conversation: messages)
        appendAssistantMessage(reply)
    }

    private func openingInsight(for snapshot: HealthSnapshot) -> String {
        let metricNames = snapshot.metrics.map(\.title).joined(separator: ", ")
        return "I refreshed your Health snapshot and found: \(metricNames). Ask me what stands out, how your recovery looks, or what changed after a workout."
    }

    private func appendUserMessage(_ text: String) {
        messages.append(ChatMessage(role: .user, text: text, createdAt: Date()))
        trimMessageHistory()
    }

    private func appendAssistantMessage(_ text: String) {
        messages.append(ChatMessage(role: .assistant, text: text, createdAt: Date()))
        trimMessageHistory()
    }

    private func trimMessageHistory() {
        guard messages.count > maxRetainedMessages else { return }
        messages = Array(messages.suffix(maxRetainedMessages))
    }
}
