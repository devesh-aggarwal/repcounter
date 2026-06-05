import Foundation

/// A single turn in the AI coach conversation. Kept in-memory for the duration
/// of the chat — persistence is a future improvement.
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    var text: String
    /// True while a streamed assistant turn is still receiving deltas.
    var isStreaming: Bool = false

    enum Role: Equatable {
        case user
        case assistant

        var wireValue: String {
            switch self {
            case .user: return "user"
            case .assistant: return "assistant"
            }
        }
    }
}
