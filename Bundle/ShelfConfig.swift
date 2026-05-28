import AppKit

enum ShelfConfig {
    static let slotCount: Int = 7
    static let slotSize: CGFloat = 56
    static let slotSpacing: CGFloat = 12
    static let padding: CGFloat = 16
    static let cornerRadius: CGFloat = 20
    static let dragHandleHeight: CGFloat = 24

    static var panelSize: CGSize {
        let height = CGFloat(slotCount) * slotSize
                   + CGFloat(slotCount - 1) * slotSpacing
                   + padding * 2
                   + dragHandleHeight
        let width = slotSize + padding * 2
        return CGSize(width: width, height: height)
    }

    static var savedPosition: CGPoint {
        get {
            let x = UserDefaults.standard.double(forKey: "shelf.position.x")
            let y = UserDefaults.standard.double(forKey: "shelf.position.y")
            guard x != 0 || y != 0 else { return defaultPosition }
            return CGPoint(x: x, y: y)
        }
        set {
            UserDefaults.standard.set(newValue.x, forKey: "shelf.position.x")
            UserDefaults.standard.set(newValue.y, forKey: "shelf.position.y")
        }
    }

    static var defaultPosition: CGPoint {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        return CGPoint(
            x: frame.minX + 40,
            y: frame.midY - panelSize.height / 2
        )
    }
}
