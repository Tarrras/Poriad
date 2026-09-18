import SwiftUI
import Shared

/// Карусель під мапою. Окреме подання, щоб `scrollPosition` перемальовував лише її, а не мапу з
/// контролами. Карусель і мапа ділять один вибір; обидва напрямки виходять, коли id вже збігається.
struct EventDeck: View {
    let events: [Event]
    let selectedID: String?
    let savedIDs: Set<String>
    /// Змінюється, коли треба повернути карусель на початок (кнопка «до міста»).
    let resetToken: Int
    let select: (String) -> Void
    let open: (String) -> Void
    let toggleSaved: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var carouselID: String?
    /// Відкладений вибір події. Див. `.onChange(of: carouselID)`.
    @State private var settle: Task<Void, Never>?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Space.md) {
                ForEach(events, id: \.id) { event in
                    EventMapCard(
                        event: event, focused: event.id == selectedID,
                        saved: savedIDs.contains(event.id),
                        onSave: { toggleSaved(event.id) }
                    ) { open(event.id) }
                    .containerRelativeFrame(.horizontal, count: 10, span: 9, spacing: Space.md)
                    .id(event.id)
                }
            }.scrollTargetLayout()
        }
        // Відступ несе вміст, смуга йде від краю до краю: звужена смуга не обрізала сусідні
        // картки, і вони висіли над мапою блідою плямою. Запас на тінь більший, ніж у решти стрічок.
        // Висота від картки: смуга прокрутки без власної висоти забирає все, що дадуть.
        .frame(height: mapCardHeight + 2 * deckSpread)
        .railContentPadding(spread: deckSpread)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $carouselID)
        .onChange(of: carouselID) { _, value in
            guard let value else { return }
            // Вибір чекає зупинки каруселі: `scrollPosition` віддає id кожної картки під час
            // інерції, а вибір публікує стан і рухає камеру. На iOS 17 нема `onScrollPhaseChange`,
            // тож чекаємо, поки id перестане мінятись.
            settle?.cancel()
            settle = Task { @MainActor in
                try? await Task.sleep(nanoseconds: settleDelay)
                guard !Task.isCancelled, value != selectedID else { return }
                select(value)
            }
        }
        // Нова карусель стає на вибране, а не на першу картку: інакше перша ж позиція прокрутки
        // обирала її і перебивала подію, з якою прийшли з деталей.
        .onAppear { if let selectedID, events.contains(where: { $0.id == selectedID }) { carouselID = selectedID } }
        .onChange(of: selectedID) { _, value in
            // Картки ще нема у вікні: прокрутка на неї не стане, а позиція лишиться чужою.
            guard let value, value != carouselID, events.contains(where: { $0.id == value }) else { return }
            if reduceMotion { carouselID = value } else { withAnimation { carouselID = value } }
        }
        // Картка вибраної події доїхала пізніше за вибір.
        .onChange(of: events.contains { $0.id == selectedID }) { _, present in
            if present, let selectedID, selectedID != carouselID { carouselID = selectedID }
        }
        .onChange(of: resetToken) { _, _ in carouselID = nil }
        .onDisappear { settle?.cancel(); settle = nil }
    }
}

/// Запас на тінь картки каруселі: на `Elevation.overlay` тінь виходить далеко за межі.
private let deckSpread: CGFloat = Space.xl

/// Скільки чекати зупинки каруселі: досить, щоб пропустити інерцію, замало, щоб вибір відчувався запізнілим.
private let settleDelay: UInt64 = 180_000_000
