import SwiftUI

/// Le spectre est une vue macOS animée en continu : la première animation SwiftUI lancée après son
/// arrivée ne démarrait pas (la pastille restait figée jusqu'à la mise à jour suivante). On en lance
/// une, invisible, juste après son apparition, pour que les vraies animations ne soient jamais les premières.
struct FirstAnimationWarmUp: ViewModifier {
    @State private var tick = false

    func body(content: Content) -> some View {
        content
            .background(Color.clear.opacity(tick ? 0.001 : 0))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.linear(duration: 0.05)) { tick.toggle() }
                }
            }
    }
}

// MARK: - Appareil connecté, Mac chargé

/// Apparition avec un petit rebond, comme sur iPhone.
struct PopIn: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.3)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.spring(duration: 0.5, bounce: 0.5).delay(0.1)) { shown = true }
            }
    }
}
