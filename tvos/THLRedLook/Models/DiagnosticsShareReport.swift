import Foundation

public struct DiagnosticsShareReport: Identifiable {
    public let id = UUID()
    public let text: String

    public init(text: String) {
        self.text = text
    }
}
