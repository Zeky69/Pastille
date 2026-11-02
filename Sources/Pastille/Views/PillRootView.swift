import SwiftUI

/// La forme noire change de taille avec un ressort ; le contenu, lui, garde une taille fixe
/// et se révèle par masque + flou, ce qui évite tout recalcul de mise en page pendant l'animation.
struct PillRootView: View {
    @ObservedObject var viewModel: PillViewModel
    var onOpenSettings: () -> Void
    @AppStorage(Appearance.musicStyleKey) private var musicStyle = Appearance.MusicStyle.artwork.rawValue
    @AppStorage(Appearance.homeLayoutKey) private var homeLayout = Appearance.HomeLayout.musicAndCalendar.rawValue
    @AppStorage(Appearance.materialKey) private var material = Appearance.PillMaterial.black.rawValue

    /// Verre liquide seulement pastille ouverte : fermée, elle reste noire comme l'encoche.
    private var showsGlass: Bool {
        material == Appearance.PillMaterial.glass.rawValue && viewModel.isExpanded
    }

    /// Style « Immersif » : la pochette floutée couvre toute la pastille ouverte (page d'accueil).
    private var showsImmersiveBackground: Bool {
        musicStyle == Appearance.MusicStyle.immersive.rawValue
            && homeLayout != Appearance.HomeLayout.calendarOnly.rawValue
            && viewModel.tab == .home
    }

    private var topRadius: CGFloat { viewModel.isExpanded ? 19 : 6 }
    private var bottomRadius: CGFloat { viewModel.isExpanded ? 24 : viewModel.extraHeight > 0 ? 20 : 14 }

    var body: some View {
        let size = viewModel.currentSize
        let shape = PillShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)

        ZStack(alignment: .top) {
            PillBackground(shape: shape, size: size, canvas: viewModel.expandedSize,
                           usesGlass: material == Appearance.PillMaterial.glass.rawValue,
                           revealed: viewModel.isExpanded)
                .shadow(color: .black.opacity(viewModel.isExpanded ? (showsGlass ? 0.3 : 0.5) : 0),
                        radius: viewModel.isExpanded ? 14 : 0, y: 6)

            content
                .frame(width: viewModel.expandedSize.width, height: viewModel.expandedSize.height, alignment: .top)
                .mask(alignment: .top) {
                    shape.frame(width: size.width, height: size.height)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // On attend que la pastille se soit repliée dans l'encoche avant de l'effacer ; au retour, elle
        // réapparaît tout de suite pour pouvoir se déplier.
        .opacity(viewModel.isConcealed ? 0 : 1)
        .animation(viewModel.isConcealed ? .easeOut(duration: 0.25).delay(0.45) : .easeIn(duration: 0.1),
                   value: viewModel.isConcealed)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        ZStack(alignment: .top) {
            if viewModel.isExpanded {
                ExpandedPillView(viewModel: viewModel, onOpenSettings: onOpenSettings)
                    .padding(.horizontal, Appearance.horizontalPadding)
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
                    .frame(width: viewModel.compactSize.width, height: viewModel.compactSize.height, alignment: .top)
                    .transition(.opacity.animation(.easeOut(duration: 0.12)))
            }
        }
    }
}

/// Fond de la pastille : noir, ou Liquid Glass (macOS 26 et plus ; avant, un verre dépoli classique).
/// Verre fumé : nettement teinté de sombre, pour que le noir de l'encoche ne tranche pas avec la
/// transparence et que le texte blanc reste lisible sur n'importe quel fond.
private struct PillBackground: View {
    let shape: PillShape
    /// Taille animée de la pastille.
    let size: CGSize
    /// Taille ouverte : le verre est posé une fois à cette taille, puis découpé par la forme animée.
    let canvas: CGSize
    /// Réglage « Liquid Glass » choisi.
    let usesGlass: Bool
    /// Pastille ouverte : le verre se dévoile ; fermée, elle reste noire comme l'encoche.
    let revealed: Bool

    var body: some View {
        // Le verre ne s'anime pas lui-même (sa propre physique ne suivrait pas celle de la pastille) :
        // il reste fixe, sous un voile noir qui s'efface, et c'est la découpe par la forme qui grandit,
        // exactement comme pour le contenu.
        ZStack(alignment: .top) {
            if usesGlass {
                glassLayer
                // Voile sombre par-dessus le verre : quel que soit l'état que macOS lui donne (fenêtre
                // inactive, page claire derrière), le résultat reste fumé.
                Color.black.opacity(0.3)
            }
            Color.black
                .opacity(usesGlass && revealed ? 0 : 1)
                .animation(.easeInOut(duration: revealed ? 0.4 : 0.25), value: revealed)
        }
        .frame(width: max(canvas.width, size.width), height: max(canvas.height, size.height), alignment: .top)
        .mask(alignment: .top) { shape.frame(width: size.width, height: size.height) }
        .overlay(alignment: .top) {
            // Liseré clair sur le bord, plus marqué en haut, comme le reflet du verre.
            shape
                .stroke(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                .frame(width: size.width, height: size.height)
                .opacity(usesGlass && revealed ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: revealed)
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var glassLayer: some View {
        if #available(macOS 26, *) {
            Color.clear.glassEffect(.regular.tint(.black.opacity(0.62)), in: Rectangle())
        } else {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.55))
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
