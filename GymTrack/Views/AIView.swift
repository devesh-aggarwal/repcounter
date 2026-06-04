import SwiftUI
import SwiftData

/// Tab 3 — Coach. Typography-led conversation. No bubble chrome on the
/// assistant side: the coach speaks in body type and full-width markdown;
/// user messages get a quiet, right-aligned chip. Empty state is one question.
struct AIView: View {
    @Query(sort: \Exercise.sortIndex) private var exercises: [Exercise]
    @Bindable private var prefs = Preferences.shared

    @State private var input: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var isResponding: Bool = false
    @State private var errorBanner: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if prefs.openAIAPIKey.isEmpty {
                    setupView
                } else {
                    chatView
                }
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !prefs.openAIAPIKey.isEmpty && !messages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation { messages = [] }
                            Haptics.impact()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .accessibilityLabel("Clear conversation")
                    }
                }
            }
        }
    }

    // MARK: Setup state

    private var setupView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.accentGradient)
            Text("Set up your coach")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("Add your OpenAI API key in Settings to chat with a coach that knows your full training history.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Text("Your key stays on this device.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
        }
        .padding(.vertical, 40)
    }

    // MARK: Chat state

    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if messages.isEmpty {
                            heroPrompt
                        } else {
                            ForEach(messages) { message in
                                turn(for: message)
                                    .id(message.id)
                            }
                            if let errorBanner {
                                errorView(errorBanner)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: messages.last?.text) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            inputBar
        }
    }

    /// Empty-state hero: one elegant prompt, no chips, no clutter.
    private var heroPrompt: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer().frame(height: 60)
            Text(greeting)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .tracking(2)
            Text(openingQuestion)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(2)
            Text("I know your full program, your numbers, and your schedule. Ask anything.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)
            Spacer().frame(height: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "GOOD MORNING"
        case 12..<17: return "GOOD AFTERNOON"
        case 17..<22: return "GOOD EVENING"
        default: return "WELCOME BACK"
        }
    }

    /// Rotates a daily-ish question — the same hash per calendar day so it
    /// doesn't shuffle on every view appearance.
    private var openingQuestion: String {
        let questions = [
            "What should you focus on today?",
            "Where's your training trending?",
            "Ready to plan your next workout?",
            "What's been hardest this week?"
        ]
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return questions[day % questions.count]
    }

    // MARK: Turns

    @ViewBuilder
    private func turn(for message: ChatMessage) -> some View {
        if message.role == .user {
            userTurn(message)
        } else {
            assistantTurn(message)
        }
    }

    private func userTurn(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 50)
            Text(message.text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .textSelection(.enabled)
        }
    }

    private func assistantTurn(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.text.isEmpty && message.isStreaming {
                Text("Thinking…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                MarkdownText(markdown: message.text, exercises: exercises)
            }
            if message.isStreaming && !message.text.isEmpty {
                streamingDots
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private var streamingDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.textTertiary)
                    .frame(width: 5, height: 5)
                    .scaleEffect(0.9)
                    .opacity(0.5)
                    .animation(
                        .easeInOut(duration: 0.7)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                        value: true
                    )
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: "#FF6E40"))
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "#FF6E40").opacity(0.12))
        )
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(
                "Message",
                text: $input,
                prompt: Text("Ask your coach…").foregroundColor(Theme.textTertiary),
                axis: .vertical
            )
            .lineLimit(1...4)
            .font(.system(size: 15))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 1)
                    )
            )
            .focused($inputFocused)
            .disabled(isResponding)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(canSend ? .black : Theme.textTertiary)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle().fill(canSend ? Theme.accent : Theme.fill)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: canSend)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Theme.background)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
    }

    // MARK: - Networking

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        let userMessage = ChatMessage(role: .user, text: text)
        let assistantMessage = ChatMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(userMessage)
        let assistantID = assistantMessage.id
        messages.append(assistantMessage)
        input = ""
        errorBanner = nil
        isResponding = true
        inputFocused = false
        Haptics.impact(.light)

        let history = Array(messages.dropLast())
        let systemPrompt = AIContextBuilder.systemPrompt(exercises: exercises)
        let client = OpenAIClient(apiKey: prefs.openAIAPIKey)

        Task {
            do {
                try await client.streamReply(
                    systemPrompt: systemPrompt,
                    history: history
                ) { delta in
                    await MainActor.run {
                        if let index = messages.firstIndex(where: { $0.id == assistantID }) {
                            messages[index].text += delta
                        }
                    }
                }
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == assistantID }) {
                        messages[index].isStreaming = false
                    }
                    isResponding = false
                    Haptics.success()
                }
            } catch {
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == assistantID }),
                       messages[index].text.isEmpty {
                        messages.remove(at: index)
                    } else if let index = messages.firstIndex(where: { $0.id == assistantID }) {
                        messages[index].isStreaming = false
                    }
                    errorBanner = error.localizedDescription
                    isResponding = false
                    Haptics.impact(.heavy)
                }
            }
        }
    }
}

#Preview {
    AIView()
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
