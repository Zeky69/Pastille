import SwiftUI

/// Appareils Bluetooth connectés : un anneau de batterie par appareil, son icône au centre.
struct BluetoothDevicesView: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        HStack(spacing: 6) {
            ForEach(bluetooth.devices) { device in
                DeviceBatteryRing(device: device)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

private struct DeviceBatteryRing: View {
    let device: BluetoothDevice
    @State private var isHovered = false

    /// Vert en charge, rouge quand c'est bas, blanc sinon.
    private var color: Color {
        if device.isCharging { return .green }
        return device.level <= 20 ? .red : .white
    }

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: CGFloat(device.level) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // Au survol, le pourcentage remplace l'icône.
            if isHovered {
                Text("\(device.level)")
                    .font(.system(size: 8, weight: .bold).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .transition(.blurReplace)
            } else {
                Image(systemName: device.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .transition(.blurReplace)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 20, height: 20)
        .overlay(alignment: .bottomTrailing) {
            if device.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 6, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 9, height: 9)
                    .background(Circle().fill(.green))
                    .offset(x: 3, y: 2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.3), value: device.isCharging)
        .contentShape(Circle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) { isHovered = hovering }
        }
        .help("\(device.name) — \(device.detail)\(device.isCharging ? " · en charge" : "")")
    }
}
