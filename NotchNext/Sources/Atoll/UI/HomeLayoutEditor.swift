import SwiftUI
import UniformTypeIdentifiers

struct HomeLayoutEditor: View {
    @EnvironmentObject var settings: SettingsStore
    @Binding var selection: HomeWidget?
    @State private var resizeOrigin: Double?
    @State private var resizeScale = 1.0
    @State private var draggedWidget: HomeWidget?
    private var widgets: [HomeWidget] { HomeWidget.decode(settings.widgetOrder) }
    private var selected: HomeWidget? { selection ?? widgets.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(settings.language == "ko" ? "끌어서 순서 변경 · 선택한 위젯의 오른쪽 손잡이로 너비 조절" : "Drag to reorder · resize a selected widget using its right edge")
                .font(.caption).foregroundStyle(.secondary)
            GeometryReader { geometry in
                let total = widgets.reduce(0.0) { $0 + settings.width(for: $1) } + Double(max(0, widgets.count - 1) * 6)
                let scale = min(1, max(1, geometry.size.width - 16) / max(1, total))
                HStack(spacing: 6 * scale) {
                    ForEach(widgets) { widget in
                        preview(widget, scale: scale)
                    }
                    if widgets.isEmpty {
                        Text(settings.language == "ko" ? "왼쪽 스위치로 위젯을 켜세요" : "Enable widgets using the switches on the left")
                            .font(.caption).frame(maxWidth: .infinity, minHeight: 70)
                    }
                }.padding(8)
            }.frame(height: 88).foregroundStyle(.white)
                .background(.black, in: RoundedRectangle(cornerRadius: 18))
            Toggle(settings.language == "ko" ? "위젯 사이 구분선 표시" : "Show dividers between widgets", isOn: $settings.widgetDividers)
                .toggleStyle(.switch).controlSize(.small).font(.caption)
            if let widget = selected {
                HStack(spacing: 10) {
                    Text(HL(widget.title)).font(.caption.bold()).frame(minWidth: 46, alignment: .leading)
                    Slider(value: Binding(get: { settings.width(for: widget) }, set: { settings.setWidth($0.rounded(), for: widget) }), in: widget.widthRange)
                        .accessibilityLabel(settings.language == "ko" ? "위젯 너비" : "Widget width")
                    Text("\(Int(settings.width(for: widget))) pt").monospacedDigit().font(.caption).frame(width: 50)
                }
                Text(settings.language == "ko" ? "최소 \(Int(widget.widthRange.lowerBound)) · 최대 \(Int(widget.widthRange.upperBound)) pt" : "Min \(Int(widget.widthRange.lowerBound)) · Max \(Int(widget.widthRange.upperBound)) pt")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func preview(_ widget: HomeWidget, scale: Double) -> some View {
            VStack(spacing: 5) {
                Image(systemName: widget.symbol).font(.system(size: 17))
                Text(HL(widget.title)).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(width: max(1, settings.width(for: widget) * scale), height: 72)
                .background(Color.white.opacity(selected == widget ? 0.20 : 0.12), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected == widget ? Color.white.opacity(0.55) : .clear, lineWidth: 1))
                .contentShape(Rectangle())
            .onTapGesture { selection = widget }
            .accessibilityLabel(HL(widget.title))
            .accessibilityAddTraits(.isButton)
            .onDrag {
                selection = widget
                draggedWidget = widget
                return NSItemProvider(object: widget.rawValue as NSString)
            }
            .onDrop(of: [.text], delegate: WidgetReorderDropDelegate(target: widget, draggedWidget: $draggedWidget, settings: settings))
            .overlay(alignment: .trailing) {
                if selected == widget {
                    Capsule().fill(Color.white.opacity(0.55)).frame(width: 3, height: 22)
                        .frame(width: 22, height: 60).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                            if resizeOrigin == nil { resizeOrigin = settings.width(for: widget); resizeScale = scale }
                            settings.setWidth((resizeOrigin! + value.translation.width / resizeScale).rounded(), for: widget)
                        }.onEnded { _ in resizeOrigin = nil })
                        .help(settings.language == "ko" ? "끌어서 너비 조절" : "Drag to resize")
                }
            }
    }
}

private struct WidgetReorderDropDelegate: DropDelegate {
    let target: HomeWidget
    @Binding var draggedWidget: HomeWidget?
    let settings: SettingsStore
    func validateDrop(info: DropInfo) -> Bool { draggedWidget != nil }
    func dropEntered(info: DropInfo) {
        guard let source = draggedWidget, source != target else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            settings.widgetOrder = HomeWidget.movingToPosition(of: target, source: source, in: HomeWidget.decode(settings.widgetOrder)).map(\.rawValue).joined(separator: ",")
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { draggedWidget = nil; return true }
}

struct ShelfLayoutEditor: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var widthOrigin: Double?
    @State private var widthScale = 1.0
    @State private var airOrigin: Double?
    @State private var airScale = 1.0
    private var korean: Bool { settings.language == "ko" }
    var body: some View {
        VStack(spacing: 10) {
            Text(korean ? "끌어서 배치 변경 · 경계 손잡이로 AirDrop 너비 조절" : "Drag to arrange · resize AirDrop at its divider").font(.caption)
            GeometryReader { geometry in
                let scale = min(1, max(1, geometry.size.width - 20) / 1100)
                // Convert every dimension with the same scale so drag distance
                // and the actual drop-zone width agree at every preview size.
                let airDrop = ShelfSizing.airDrop(settings.airDropWidth) * scale
                HStack(spacing: 10 * scale) {
                    if !settings.shelfAirDropTrailing {
                        airDropTile(width: airDrop, scale: scale)
                        tile(HL("Shelf"))
                    } else {
                        tile(HL("Shelf"))
                        airDropTile(width: airDrop, scale: scale)
                    }
                }.padding(.horizontal, 28 * scale).padding(.vertical, 10)
                    .frame(width: settings.shelfWidth * scale)
                    .background(.black, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .trailing) {
                        resizeHandle(label: korean ? "파일 보관함 전체 너비" : "Overall shelf width", value: settings.shelfWidth)
                            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("shelfPreview")).onChanged { value in
                                if widthOrigin == nil { widthOrigin = settings.shelfWidth; widthScale = scale }
                                settings.shelfWidth = min(1100, max(480, (widthOrigin! + value.translation.width / widthScale).rounded()))
                            }.onEnded { _ in widthOrigin = nil })
                            .accessibilityAdjustableAction { direction in
                                settings.shelfWidth = min(1100, max(480, settings.shelfWidth + (direction == .increment ? 10 : -10)))
                            }
                    }
            }.frame(height: 75).foregroundStyle(.white).coordinateSpace(name: "shelfPreview")
            Text(korean ? "AirDrop 안쪽 손잡이: AirDrop 너비 · 바깥 손잡이: 보관함 전체 너비" : "Inner handle: AirDrop width · outer handle: entire shelf width")
                .font(.caption).foregroundStyle(.secondary)
            shelfSizeRow(korean ? "파일 보관함 너비" : "Shelf width", value: $settings.shelfWidth, range: 480...1100)
            shelfSizeRow(korean ? "파일 보관함 높이" : "Shelf height", value: $settings.shelfHeight, range: 220...560)
            shelfSizeRow(korean ? "AirDrop 영역 너비" : "AirDrop width", value: Binding(get: { ShelfSizing.airDrop(settings.airDropWidth) }, set: { settings.airDropWidth = ShelfSizing.airDrop($0) }), range: ShelfSizing.airDropRange)
            Text(korean ? "AirDrop 너비 72–240 pt · 높이는 파일 보관함과 함께 변경됩니다." : "AirDrop width 72–240 pt · height follows the shelf.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(.top, 14)
    }
    private func airDropTile(width: Double, scale: Double) -> some View {
        tile("AirDrop").frame(width: width)
            .overlay(alignment: settings.shelfAirDropTrailing ? .leading : .trailing) {
                resizeHandle(label: korean ? "AirDrop 너비 조절" : "Resize AirDrop", value: ShelfSizing.airDrop(settings.airDropWidth))
                    .highPriorityGesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("shelfPreview")).onChanged { value in
                        if airOrigin == nil { airOrigin = ShelfSizing.airDrop(settings.airDropWidth); airScale = scale }
                        settings.airDropWidth = ShelfSizing.resizedAirDrop(origin: airOrigin!, translation: value.translation.width, scale: airScale, trailing: settings.shelfAirDropTrailing)
                    }.onEnded { _ in airOrigin = nil })
                    .accessibilityAdjustableAction { direction in
                        settings.airDropWidth = ShelfSizing.airDrop(settings.airDropWidth + (direction == .increment ? 8 : -8))
                    }
            }
    }
    private func resizeHandle(label: String, value: Double) -> some View {
        Capsule().fill(.white.opacity(0.75)).frame(width: 3, height: 24)
            .frame(width: 16, height: 55).contentShape(Rectangle())
            .help(label).accessibilityElement().accessibilityLabel(label).accessibilityValue("\(Int(value)) pt")
    }
    private func shelfSizeRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 120, alignment: .leading)
            Slider(value: value, in: range).accessibilityLabel(title)
            Text("\(Int(value.wrappedValue)) pt").monospacedDigit().font(.caption).frame(width: 60)
        }
    }
    private func tile(_ title: String) -> some View {
        Text(title).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity).frame(height: 55)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .onDrag { NSItemProvider(object: title as NSString) }
            .onDrop(of: [.text], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: String.self) { raw, _ in
                    guard let raw, raw != title, ["AirDrop", HL("Shelf")].contains(raw) else { return }
                    DispatchQueue.main.async { settings.shelfAirDropTrailing.toggle() }
                }
                return true
            }
    }
}
