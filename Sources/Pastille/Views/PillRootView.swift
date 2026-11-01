import SwiftUI

/// La forme noire change de taille avec un ressort ; le contenu, lui, garde une taille fixe
/// et se révèle par masque + flou, ce qui évite tout recalcul de mise en page pendant l'animation.
struct PillRootView: View {
    @ObservedObject var viewModel: PillViewModel
    var onOpenSettings: () -> Void
    @AppStorage(Appearance.musicStyleKey) private var musicStyle = Appearance.MusicStyle.artwork.rawValue
    @AppStorage(Appearance.homeLayoutKey) private var homeLayout = Appearance.HomeLayout.musicAndCalendar.rawValue

    /// Style « Immersif » : la pochette floutée couvre toute la pastille ouverte (page d'accueil).
    private var showsImmersiveBackground: Bool {
        musicStyle == Appearance.MusicStyle.immersive.rawValue
            && homeLayout != Appearance.HomeLayout.calendarOnly.rawValue
            && viewModel.tab == .home
    }

    private var topRadius: CGFloat { viewModel.isExpanded ? 19 : 6 }
    private var bottomRadius: CGFloat { viewModel.isExpanded ? 24 : 14 }

    var body: some View {
        let size = viewModel.currentSize
        let shape = PillShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)

        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(viewModel.isExpanded ? 0.5 : 0), radius: viewModel.isExpanded ? 14 : 0, y: 6)

            content
                .frame(width: viewModel.expandedSize.width, height: viewModel.expandedSize.height, alignment: .top)
                .mask(alignment: .top) {
                    shape.frame(width: size.width, height: size.height)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        ZStack(alignment: .top) {
            if viewModel.isExpanded {
                ExpandedPillView(viewModel: viewModel, onOpenSettings: onOpenSettings)
                    .padding(.horizontal, 19 + 12)
                    .frame(width: viewModel.expandedSize.width, height: viewModel.expandedSize.height)
                    .background {
                        if showsImmersiveBackground {
                            ImmersiveBackground().transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: showsImmersiveBackground)
                    .transition(.pillContent)
            } else {
                CompactPillView(viewModel: viewModel)
                    .frame(width: viewModel.compactSize.width, height: viewModel.cutoutSize.height)
                    .transition(.opacity.animation(.easeOut(duration: 0.12)))
            }
        }
    }
}

private struct PillContentModifier: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(hidden ? 0.82 : 1, anchor: .top)
            .blur(radius: hidden ? 12 : 0)
            .opacity(hidden ? 0 : 1)
    }
}

extension AnyTransition {
    /// Le contenu « éclot » depuis la découpe : léger zoom, flou qui se dissipe, fondu.
    static var pillContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: PillContentModifier(hidden: true),
                identity: PillContentModifier(hidden: false)
            )
            .animation(.spring(duration: 0.45, bounce: 0.2).delay(0.04)),
            removal: .modifier(
                active: PillContentModifier(hidden: true),
                identity: PillContentModifier(hidden: false)
            )
            .animation(.easeIn(duration: 0.16))
        )
    }
}
