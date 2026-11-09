import UIKit

public class TVTouchCapturingView: UIView, UIGestureRecognizerDelegate {
    var onPanBegan: (() -> Void)?
    var onPanChanged: ((CGFloat) -> Void)?
    var onPanEnded: (() -> Void)?
    var onLeftArrow: (() -> Void)?
    var onRightArrow: (() -> Void)?
    var onUpArrow: (() -> Void)?
    var onDownArrow: (() -> Void)?
    var onSelect: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onMenu: (() -> Void)?

    public override var canBecomeFocused: Bool {
        return false
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        backgroundColor = .clear
        isAccessibilityElement = false

        // 1. Siri Remote 触控表面滑动手势
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = self
        addGestureRecognizer(panGesture)

        // 2. 遥控器 Left 按键专用手势（快退10秒）
        let leftTap = UITapGestureRecognizer(target: self, action: #selector(handleLeftPress))
        leftTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.leftArrow.rawValue)]
        leftTap.cancelsTouchesInView = false
        leftTap.delegate = self
        addGestureRecognizer(leftTap)

        // 3. 遥控器 Right 按键专用手势（快进10秒）
        let rightTap = UITapGestureRecognizer(target: self, action: #selector(handleRightPress))
        rightTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.rightArrow.rawValue)]
        rightTap.cancelsTouchesInView = false
        rightTap.delegate = self
        addGestureRecognizer(rightTap)

        // 4. 遥控器 Up 按键专用手势（上一集）
        let upTap = UITapGestureRecognizer(target: self, action: #selector(handleUpPress))
        upTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.upArrow.rawValue)]
        upTap.cancelsTouchesInView = false
        upTap.delegate = self
        addGestureRecognizer(upTap)

        // 5. 遥控器 Down 按键专用手势（下一集）
        let downTap = UITapGestureRecognizer(target: self, action: #selector(handleDownPress))
        downTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.downArrow.rawValue)]
        downTap.cancelsTouchesInView = false
        downTap.delegate = self
        addGestureRecognizer(downTap)

        // 6. 遥控器 Select 确认按键手势
        let selectTap = UITapGestureRecognizer(target: self, action: #selector(handleSelectPress))
        selectTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        selectTap.cancelsTouchesInView = false
        selectTap.delegate = self
        addGestureRecognizer(selectTap)

        // 7. 遥控器 Play/Pause 按键手势
        let playPauseTap = UITapGestureRecognizer(target: self, action: #selector(handlePlayPausePress))
        playPauseTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        playPauseTap.cancelsTouchesInView = false
        playPauseTap.delegate = self
        addGestureRecognizer(playPauseTap)

        // 8. 遥控器 Menu 按键手势
        let menuTap = UITapGestureRecognizer(target: self, action: #selector(handleMenuPress))
        menuTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        menuTap.cancelsTouchesInView = false
        menuTap.delegate = self
        addGestureRecognizer(menuTap)

        // 9. 遥控器触控板轻扫手势 (Swipe Right: 快进, Swipe Left: 快退, Swipe Up: 上一集, Swipe Down: 下一集)
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleRightPress))
        swipeRight.direction = .right
        swipeRight.cancelsTouchesInView = false
        swipeRight.delegate = self
        addGestureRecognizer(swipeRight)

        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleLeftPress))
        swipeLeft.direction = .left
        swipeLeft.cancelsTouchesInView = false
        swipeLeft.delegate = self
        addGestureRecognizer(swipeLeft)

        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleUpPress))
        swipeUp.direction = .up
        swipeUp.cancelsTouchesInView = false
        swipeUp.delegate = self
        addGestureRecognizer(swipeUp)

        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleDownPress))
        swipeDown.direction = .down
        swipeDown.cancelsTouchesInView = false
        swipeDown.delegate = self
        addGestureRecognizer(swipeDown)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleMenuPress() {
        print("THL_GESTURE_MENU_PRESS_CAPTURED")
        onMenu?()
    }

    @objc private func handleLeftPress() {
        print("THL_GESTURE_LEFT_PRESS_CAPTURED")
        onLeftArrow?()
    }

    @objc private func handleRightPress() {
        print("THL_GESTURE_RIGHT_PRESS_CAPTURED")
        onRightArrow?()
    }

    @objc private func handleUpPress() {
        print("THL_GESTURE_UP_PRESS_CAPTURED")
        onUpArrow?()
    }

    @objc private func handleDownPress() {
        print("THL_GESTURE_DOWN_PRESS_CAPTURED")
        onDownArrow?()
    }

    @objc private func handleSelectPress() {
        print("THL_GESTURE_SELECT_PRESS_CAPTURED")
        onSelect?()
    }

    @objc private func handlePlayPausePress() {
        print("THL_GESTURE_PLAYPAUSE_PRESS_CAPTURED")
        onPlayPause?()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            onPanBegan?()
        case .changed:
            let translation = recognizer.translation(in: self)
            onPanChanged?(translation.x)
        case .ended, .cancelled:
            onPanEnded?()
        default:
            break
        }
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesBegan(presses, with: event)
    }
}
