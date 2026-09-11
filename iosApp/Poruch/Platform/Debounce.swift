import SwiftUI

/**
 Дія, що чекає, доки значення перестане мінятись.

 Поле вводу малює те, що людина набрала, зі свого власного `@State` — це миттєво. Дорого коштує не
 малювання, а те, що зазвичай висить на `onChange`: перехід у спільний стан, новий `AppState`, і як
 наслідок — перемальовування всього екрана. На кожну літеру.

 Тому такі дії відкладаються. Затримка тут не «щоб рідше», а «щоб один раз на слово»: усе, що
 відбувається далі, вже має власне відкладення перед мережею, тож ці кількасот мілісекунд не
 додаються до відчуття, а зникають у ньому.
 */
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
    /// Викликає [action] лише тоді, коли [value] перестало мінятись на [delay].
    func onSettled<Value: Equatable>(
        _ value: Value,
        after delay: Duration = .milliseconds(150),
        perform action: @escaping (Value) -> Void
    ) -> some View {
        modifier(SettledChange(value: value, delay: delay, action: action))
    }
}
