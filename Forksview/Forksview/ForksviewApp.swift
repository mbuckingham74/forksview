import AppKit

@main
@MainActor
enum ForksviewApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()

        application.setActivationPolicy(.regular)
        application.delegate = delegate
        MainMenu.install(on: application)
        application.run()

        withExtendedLifetime(delegate) {}
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        true
    }
}

@MainActor
private enum MainMenu {
    static func install(on application: NSApplication) {
        let mainMenu = NSMenu()
        mainMenu.addItem(applicationMenu(for: application))
        mainMenu.addItem(fileMenu())
        mainMenu.addItem(editMenu())
        mainMenu.addItem(windowMenu(for: application))
        mainMenu.addItem(helpMenu())
        application.mainMenu = mainMenu
    }

    private static func applicationMenu(for application: NSApplication) -> NSMenuItem {
        let item = NSMenuItem(title: "Forksview", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Forksview")
        item.submenu = menu

        menu.addItem(withTitle: "About Forksview", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        menu.addItem(servicesItem)
        application.servicesMenu = servicesMenu

        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Forksview", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")

        let hideOthers = menu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")

        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Forksview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = application
        return item
    }

    private static func fileMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "File")
        item.submenu = menu

        let documentController = NSDocumentController.shared
        let newDocument = menu.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        newDocument.target = documentController
        let openDocument = menu.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        openDocument.target = documentController

        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(withTitle: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")

        let saveAs = menu.addItem(withTitle: "Save As…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        return item
    }

    private static func editMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Edit")
        item.submenu = menu

        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")

        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return item
    }

    private static func windowMenu(for application: NSApplication) -> NSMenuItem {
        let item = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Window")
        item.submenu = menu

        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        application.windowsMenu = menu
        return item
    }

    private static func helpMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        item.submenu = NSMenu(title: "Help")
        return item
    }
}
