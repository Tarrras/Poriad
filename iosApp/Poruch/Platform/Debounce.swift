import SwiftUI

/// Дія після паузи в змінах значення: `onChange` у спільний стан перемальовував весь екран на кожну літеру.
private struct SettledChange<Value: Equatable>: ViewModifier {
    let value: Value
    let delay: Duration
    let action: (Value) -> Void

    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onChange(of: value) { _, latest in
                pending?.cancel()
                pending = Task { @MainActor in
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled else { return }
                    action(latest)
                }
            }
            .onDisappear { pending?.cancel(); pending = nil }
    }
}

extension View {
    /// Викликає `action`, коли `value` не мінялось протягом `delay`.
    func onSettled<Value: Equatable>(
        _ value: Value,
        after delay: Duration = .milliseconds(150),
        perform action: @escaping (Value) -> Void
    ) -> some View {
        modifier(SettledChange(value: value, delay: delay, action: action))
    }
}
