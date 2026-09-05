import SwiftUI
import Shared

struct DiscoveryView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var location = LocationFinder()
    @State private var listMode = false
    @State private var citySearch = false
    @State private var create = false
    @State private var auth = false
    @State private var details = false
    @State private var onlyAvailable = false
    @State private var region: MapRegion?
    var events: [Event] { (model.state?.events ?? []).filter { !onlyAvailable || $0.attendeeCount < $0.capacity } }
    var body: some View {
        ZStack(alignment: .bottom) {
            if listMode {
                List(events, id: \.id) { event in
                    Button { model.app.selectEvent(id: event.id); details = true } label: { EventRow(event: event) }.buttonStyle(.plain)
                }.overlay { if events.isEmpty && model.state?.loading != true { ContentUnavailableView("Поки немає подій", systemImage: "calendar", description: Text("Змініть область або фільтри. Або створіть першу подію.")) } }
            } else {
                EventMap(events: events, latitude: model.state?.cityLatitude ?? 50.45, longitude: model.state?.cityLongitude ?? 30.52, selected: { model.app.selectEvent(id: $0.id) }, moved: { region = $0 }).ignoresSafeArea(edges: .bottom)
            }
            VStack(spacing: 12) {
                if let region, !listMode {
                    Button { model.app.searchArea(south: region.south, west: region.west, north: region.north, east: region.east); self.region = nil } label: { Label("Шукати тут", systemImage: "arrow.clockwise").font(.subheadline.weight(.semibold)).padding(12).background(.regularMaterial, in: Capsule()) }.padding(.top, 8)
                }
                Spacer()
                if events.isEmpty && model.state?.loading == false && !listMode {
                    Text("У цій області поки немає подій").font(.subheadline).padding(12).background(.regularMaterial, in: Capsule())
                }
                HStack {
                    Button { location.request() } label: { Image(systemName: "location").frame(width: 48, height: 48).background(.regularMaterial, in: Circle()) }.accessibilityLabel("Поруч зі мною")
                    Spacer()
                    Button { if model.state?.userId == nil { auth = true } else { create = true } } label: { Label("Створити", systemImage: "plus").font(.headline).padding(.horizontal, 20).frame(height: 48) }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                }
                if let event = model.state?.selectedEvent, !listMode {
                    HStack {
                        Button { details = true } label: { EventRow(event: event) }.buttonStyle(.plain)
                        Button { model.app.dismissEvent() } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }.accessibilityLabel("Закрити картку")
                    }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22)).shadow(color: .black.opacity(0.08), radius: 15, y: 5)
                }
            }.padding()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button { citySearch = true } label: { Label(model.state?.cityName ?? "Київ", systemImage: "magnifyingglass").font(.title2.bold()) }
                    Spacer()
                    Button { listMode.toggle() } label: { Image(systemName: listMode ? "map" : "list.bullet").frame(width: 44, height: 44) }.accessibilityLabel(listMode ? "Показати мапу" : "Показати список")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach([("all", "Будь-коли"), ("today", "Сьогодні"), ("weekend", "Вихідні")], id: \.0) { item in
                            Button(item.1) { model.app.setDateFilter(filter: item.0) }.buttonStyle(.bordered).tint(model.state?.dateFilter == item.0 ? .accentColor : .secondary)
                        }
                        Toggle("Є місця", isOn: $onlyAvailable).toggleStyle(.button).buttonStyle(.bordered)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(categories, id: \.0) { category in
                        Button { model.app.setCategory(category: category.0) } label: { Label(category.1, systemImage: category.2) }.buttonStyle(.bordered).tint(model.state?.category == category.0 ? .accentColor : .secondary)
                    } }
                }
                if model.state?.loading == true { ProgressView().frame(maxWidth: .infinity) }
                if model.state?.offline == true { Label("Офлайн · останні результати", systemImage: "wifi.slash").font(.caption).foregroundStyle(.secondary) }
            }.padding(.horizontal).padding(.bottom, 12).background(.bar)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $citySearch) { CitySearchView() }
        .sheet(isPresented: $create) { EventEditor(event: nil) }
        .sheet(isPresented: $auth) { NavigationStack { ProfileView() } }
        .navigationDestination(isPresented: $details) { EventDetailView() }
        .onReceive(location.$coordinate) { coordinate in
            if let coordinate { model.app.selectCity(city: CityResult(name: "Поруч зі мною", latitude: coordinate.latitude, longitude: coordinate.longitude)) }
        }
        .alert("Геолокація", isPresented: Binding(get: { location.message != nil }, set: { if !$0 { location.message = nil } })) { Button("Добре") { location.message = nil } } message: { Text(location.message ?? "") }
    }
}
struct CitySearchView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List(model.state?.cities ?? [], id: \.name) { city in
                Button { model.app.selectCity(city: city); dismiss() } label: { Label(city.name, systemImage: "mappin.and.ellipse") }
            }.searchable(text: $query, prompt: "Місто у світі")
                .onChange(of: query) { _, value in model.app.searchCity(query: value) }
                .navigationTitle("Знайти місто").toolbar { Button("Готово") { dismiss() } }
        }
    }
}
