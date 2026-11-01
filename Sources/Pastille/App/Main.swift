import AppKit

@main
enum Main {
    static func main() {
        // Mode outil : lecture fraîche des batteries Bluetooth par un processus neuf (voir BluetoothManager).
        if CommandLine.arguments.contains(BluetoothManager.levelsArgument) {
            BluetoothManager.printLevels()
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
