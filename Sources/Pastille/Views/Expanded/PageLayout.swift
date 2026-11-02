import SwiftUI

extension View {
    /// Mesure la hauteur naturelle de la page (sans l'étirer) pour que la pastille s'y ajuste.
    func measuredHeight(for tab: PillTab, in viewModel: PillViewModel) -> some View {
        fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                viewModel.reportContentHeight(height, for: tab)
            }
    }
}

/// Zones (coordonnées de la pastille) où glisser à deux doigts ne change pas de page.
@MainActor
enum PageSwipeBlockers {
    static var frames: [String: CGRect] = [:]
}

extension View {
    /// Glisser à deux doigts sur cette vue ne change pas de page (elle a ses propres gestes).
    func blocksPageSwipe(_ id: String) -> some View {
        background(
            GeometryReader { geo in
                let frame = geo.frame(in: .global)
                Color.clear
                    .onAppear { PageSwipeBlockers.frames[id] = frame }
                    .onChange(of: frame) { _, new in PageSwipeBlockers.frames[id] = new }
                    .onDisappear { PageSwipeBlockers.frames[id] = nil }
            }
        )
    }
}
