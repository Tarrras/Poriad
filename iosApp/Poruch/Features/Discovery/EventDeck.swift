import SwiftUI
import Shared

/**
 Карусель під мапою.

 Живе окремим поданням не заради охайності, а заради кадрів. `scrollPosition` пише в `@State` на
 кожній картці, повз яку йде палець, і поки цей стан належав екрану цілком, кожен такий запис
 перемальовував разом із каруселлю і мапу, і верхні контроли. Тепер перемальовується сама карусель.

 Карусель і мапа ділять один вибір: картка стала на місце — пін підсвітився; тапнули пін — карусель
 прокрутилась назад. Обидва напрямки виходять, коли id вже збігається, інакше вони ганяли б одне
 одного по колу.
 */
struct EventDeck: View {
    let events: [Event]
    let selectedID: String?
    let savedIDs: Set<String>
    /// Змінюється, коли екран просить повернути карусель на початок (кнопка «до міста»).
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
        /*
         Відступ від краю екрана несе сам вміст каруселі, а смуга прокрутки йде від краю до краю
         (див. від'ємний відступ на місці виклику).

         Смуга, звужена на поля сторінки, вміст за своїми межами не обрізала: сусідні картки
         вилазили в поля обабіч і висіли над мапою блідою плямою — здалеку це читалось як тінь
         під каруселлю. Коли смуга завширшки з екран, за її межами вже сам екран, і сусідню
         картку природно зрізає край.

         Запас на тінь тут більший, ніж у решти стрічок: картка каруселі висить над мапою на
         `Elevation.overlay`, і її тінь виходить далеко за власні межі.
         */
        // Висота — від картки, а не від місця, що лишилось: у стосі з розпоркою смуга прокрутки
        // без власної висоти забирає все, що їй запропонують.
        .frame(height: mapCardHeight + 2 * deckSpread)
        .railContentPadding(spread: deckSpread)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $carouselID)
        .onChange(of: carouselID) { _, value in
            guard let value else { return }
            /*
             Вибір події чекає, доки карусель зупиниться.

             `scrollPosition` віддає id кожної картки, повз яку проходить інерція, — за один змах
             їх десяток. А вибір не безкоштовний: він тягне деталі події з мережі й публікує новий
             стан, тобто змушує мапу перебудувати піни й почати нову анімацію камери. Десять разів
             поспіль — це і є фріз.

             Android тут просто нічого не робить, поки `listState.isScrollInProgress`. На iOS 17
             такого прапорця немає (`onScrollPhaseChange` — з 18.0), тож еквівалент — зачекати,
             доки id перестане мінятись.
             */
            settle?.cancel()
            settle = Task { @MainActor in
                try? await Task.sleep(nanoseconds: settleDelay)
                guard !Task.isCancelled, value != selectedID else { return }
                select(value)
            }
        }
        .onChange(of: selectedID) { _, value in
            guard let value, value != carouselID else { return }
            if reduceMotion { carouselID = value } else { withAnimation { carouselID = value } }
        }
        .onChange(of: resetToken) { _, _ in carouselID = nil }
        .onDisappear { settle?.cancel(); settle = nil }
    }
}

/// Запас на тінь картки каруселі: вона висить над мапою на `Elevation.overlay`, і тінь виходить
/// далеко за власні межі картки.
private let deckSpread: CGFloat = Space.xl

/// Скільки чекати, доки карусель зупиниться. Досить, щоб пропустити інерцію, і замало, щоб вибір
/// відчувався запізнілим після того, як картка стала на місце.
private let settleDelay: UInt64 = 180_000_000
