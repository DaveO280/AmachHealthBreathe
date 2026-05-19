import SwiftUI
import AmachBreatheShared

/// Reusable per-session AI coach thread (detail history + session completion).
struct CoachConversationView: View {

    let record: BreathingSessionRecord
    var style: Style = .card
    var showsHeader: Bool = true

    @EnvironmentObject private var sessionService: SessionService

    @State private var messages: [CoachingHistoryMessage] = []
    @State private var draft = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var composerFocused: Bool

    enum Style {
        case card
        case embedded
    }

    private var facts: CoachingSessionFacts {
        CoachingSessionFacts(record: record)
    }

    private var hasThread: Bool { !messages.isEmpty }

    private var coachSubtitle: String? {
        guard let metrics = record.audioBreathMetrics else { return nil }
        if metrics.permissionGranted, metrics.estimatedBreathingBPM != nil {
            return "Includes microphone timing estimate · no raw audio sent"
        }
        return "Audio tracking was on; timing estimate was limited"
    }

    var body: some View {
        Group {
            switch style {
            case .card:
                cardContent
            case .embedded:
                embeddedContent
            }
        }
        .onAppear { reloadFromPersistence() }
        .onChange(of: sessionService.sessions) { _, _ in reloadFromPersistence() }
    }

    // MARK: - Layout

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: AmachSpacing.md) {
            header
            threadBody
            if !hasThread { emptyState }
            suggestedPrompts
            composer
            if let errorMessage {
                Text(errorMessage)
                    .font(AmachType.tiny)
                    .foregroundStyle(Color.amachDestructive)
            }
        }
        .padding(AmachSpacing.cardPadding)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
    }

    private var embeddedContent: some View {
        VStack(alignment: .leading, spacing: AmachSpacing.sm) {
            if showsHeader { header }
            threadBody
            if !hasThread { emptyState }
            suggestedPrompts
            composer
            if let errorMessage {
                Text(errorMessage)
                    .font(AmachType.tiny)
                    .foregroundStyle(Color.amachDestructive)
            }
        }
        .padding(AmachSpacing.md)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AmachSpacing.xs) {
            HStack(spacing: AmachSpacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.amachPrimaryBright)
                Text("Coach")
                    .font(AmachType.h3)
                    .foregroundStyle(Color.amachTextPrimary)
                Spacer()
            }
            if let coachSubtitle {
                Text(coachSubtitle)
                    .font(AmachType.tiny)
                    .foregroundStyle(Color.amachTextSecondary)
            } else {
                Text("Ask about this session using saved metrics only.")
                    .font(AmachType.tiny)
                    .foregroundStyle(Color.amachTextSecondary)
            }
        }
    }

    @ViewBuilder
    private var threadBody: some View {
        if hasThread {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AmachSpacing.sm) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                            messageBubble(message)
                                .id(index)
                        }
                        if isLoading {
                            HStack(spacing: AmachSpacing.xs) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Coach is thinking…")
                                    .font(AmachType.caption)
                                    .foregroundStyle(Color.amachTextSecondary)
                            }
                            .padding(.leading, AmachSpacing.sm)
                        }
                    }
                }
                .frame(maxHeight: style == .embedded ? 220 : 320)
                .onChange(of: messages.count) { _, count in
                    guard count > 0 else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AmachSpacing.sm) {
            Text("Get a short summary of this session, then ask follow-up questions.")
                .font(AmachType.caption)
                .foregroundStyle(Color.amachTextSecondary)
            Button {
                requestInitialInsight()
            } label: {
                HStack {
                    if isLoading && !hasThread {
                        ProgressView()
                            .tint(Color.amachTextPrimary)
                    }
                    Text("Get insight")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.amachPrimary)
            .disabled(isLoading)
        }
    }

    private var suggestedPrompts: some View {
        let prompts = suggestedPromptLabels
        return Group {
            if !prompts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AmachSpacing.xs) {
                        ForEach(prompts, id: \.self) { prompt in
                            Button(prompt) {
                                draft = prompt
                                sendUserMessage(prompt)
                            }
                            .font(AmachType.tiny.weight(.medium))
                            .foregroundStyle(Color.amachPrimaryBright)
                            .padding(.horizontal, AmachSpacing.sm)
                            .padding(.vertical, 6)
                            .background(Color.amachPrimary.opacity(0.12))
                            .clipShape(Capsule())
                            .disabled(isLoading)
                        }
                    }
                }
            }
        }
    }

    private var suggestedPromptLabels: [String] {
        var labels = [
            "Why was coherence low?",
            "How was my breathing timing?",
            "What should I try next session?"
        ]
        if record.audioBreathMetrics == nil {
            labels.removeAll { $0 == "How was my breathing timing?" }
        }
        return labels
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: AmachSpacing.sm) {
            TextField("Ask the coach…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(AmachType.body)
                .focused($composerFocused)
                .disabled(isLoading)

            Button {
                sendUserMessage(draft)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.amachPrimary : Color.amachTextTertiary)
            }
            .disabled(!canSend || isLoading)
            .accessibilityLabel("Send message")
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Bubbles

    private func messageBubble(_ message: CoachingHistoryMessage) -> some View {
        HStack {
            if message.isUser { Spacer(minLength: 48) }
            Text(message.content)
                .font(AmachType.caption)
                .foregroundStyle(message.isUser ? Color.white : Color.amachTextPrimary)
                .padding(.horizontal, AmachSpacing.sm)
                .padding(.vertical, AmachSpacing.xs)
                .background(message.isUser ? Color.amachPrimary : Color.amachBg)
                .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
            if message.isAssistant { Spacer(minLength: 48) }
        }
    }

    // MARK: - Actions

    private func reloadFromPersistence() {
        let state = sessionService.coachingState(forSessionId: record.id)
        if state.messages != messages {
            messages = state.messages
        }
    }

    private func persist() {
        let insight = messages.last(where: \.isAssistant).map {
            CoachingInsight(content: $0.content)
        }
        sessionService.updateCoaching(
            forSessionId: record.id,
            coaching: SessionCoachingState(messages: messages, lastInsight: insight)
        )
    }

    private func requestInitialInsight() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let insight = try await AmachAPIClient.shared.generateCoachingInsight(for: record)
                await MainActor.run {
                    messages = [
                        .user(CoachingInsightRequest.initialUserDisplayMessage),
                        .assistant(insight.content)
                    ]
                    draft = ""
                    isLoading = false
                    persist()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Coach is unavailable right now."
                    isLoading = false
                }
            }
        }
    }

    private func sendUserMessage(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        let historyForAPI = messages.dropLast() // exclude optimistic user bubble
        let apiMessage: String
        if historyForAPI.isEmpty {
            apiMessage = """
            \(CoachingInsightRequest.initialPrompt(for: facts))
            Focus your answer on: \(text)
            """
        } else {
            apiMessage = "\(CoachingInsightRequest.followUpSystemHint(for: facts))\n\nUser question: \(text)"
        }

        messages.append(.user(text))
        draft = ""
        isLoading = true
        errorMessage = nil
        composerFocused = false

        Task {
            do {
                let insight = try await AmachAPIClient.shared.sendCoachingMessage(
                    facts: facts,
                    history: historyForAPI,
                    message: apiMessage
                )
                await MainActor.run {
                    messages.append(.assistant(insight.content))
                    isLoading = false
                    persist()
                }
            } catch {
                await MainActor.run {
                    if messages.last?.content == text, messages.last?.isUser == true {
                        messages.removeLast()
                    }
                    errorMessage = "Could not reach the coach. Try again."
                    isLoading = false
                }
            }
        }
    }
}
