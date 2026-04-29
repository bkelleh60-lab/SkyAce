import UIKit

/// Apple Kids category parental gate (App Review Guideline 1.3).
///
/// Two layers must be cleared before `onGatePassedCompletion` fires:
///   1. A two-step math problem in the form `(A × B) + C` or `(A × B) − C`,
///      entered via a custom on-screen numeric keypad. The system keyboard is
///      never invoked.
///   2. A press-and-hold confirmation button that must be held for 3 seconds.
///      Releasing early resets progress.
///
/// Within a single app session (launch → termination) no math problem is
/// reused — the static `seenProblems` set guards against repeats.
///
/// The correct answer is held in a `private` stored property and is never
/// surfaced through any label, log, or print/os_log call.
final class ParentalGateViewController: UIViewController {

    // MARK: - Public callbacks

    /// Fires when both layers (math + 3s hold) are cleared. The controller
    /// dismisses itself before invoking the closure.
    var onGatePassedCompletion: (() -> Void)?

    /// Fires when the user taps Cancel. The controller dismisses itself
    /// before invoking the closure.
    var onCancel: (() -> Void)?

    // MARK: - Session-wide problem memory

    /// Problems already shown in this app session. Cleared at launch only.
    /// Key format: `"AxB+C"` / `"AxB-C"`.
    private static var seenProblems: Set<String> = []

    // MARK: - State (private — never exposed)

    private var operandA: Int = 0
    private var operandB: Int = 0
    private var operandC: Int = 0
    private var usesPlus: Bool = true
    private var expectedAnswer: Int = 0

    private var enteredText: String = "" {
        didSet { refreshInputDisplay() }
    }
    private static let maxInputLength = 3

    private var mathPassed: Bool = false

    // Hold-to-unlock
    private static let holdDuration: TimeInterval = 3.0
    private var holdProgress: Double = 0.0
    private var holdTimer: Timer?
    private var holdStart: CFTimeInterval = 0

    // MARK: - Views

    private let dimView           = UIView()
    private let card              = UIView()
    private let titleLabel        = UILabel()
    private let instructionLabel  = UILabel()
    private let questionLabel     = UILabel()
    private let inputDisplay      = UILabel()
    private let errorLabel        = UILabel()
    private let keypadStack       = UIStackView()
    private let checkButton       = UIButton(type: .system)
    private let holdButton        = UIButton(type: .custom)
    private let holdProgressFill  = UIView()
    private let holdLabel         = UILabel()
    private let holdHintLabel     = UILabel()
    private let cancelButton      = UIButton(type: .system)

    // Constraints toggled when transitioning to the hold layer.
    private var keypadHiddenConstraints: [NSLayoutConstraint] = []
    private var holdProgressWidth: NSLayoutConstraint?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        modalPresentationStyle = .overFullScreen
        buildHierarchy()
        buildLayout()
        buildStyle()
        regenerateProblem()
        showMathLayer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        invalidateHoldTimer()
    }

    deinit {
        invalidateHoldTimer()
    }

    // MARK: - Build

    private func buildHierarchy() {
        [dimView, card].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        [titleLabel, instructionLabel, questionLabel, inputDisplay, errorLabel,
         keypadStack, checkButton, holdButton, holdHintLabel, cancelButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview($0)
        }

        // Hold button has a left-to-right fill overlay and a centered label.
        holdProgressFill.translatesAutoresizingMaskIntoConstraints = false
        holdLabel.translatesAutoresizingMaskIntoConstraints = false
        holdButton.addSubview(holdProgressFill)
        holdButton.addSubview(holdLabel)

        buildKeypad()
    }

    private func buildKeypad() {
        keypadStack.axis = .vertical
        keypadStack.alignment = .fill
        keypadStack.distribution = .fillEqually
        keypadStack.spacing = 8

        // Layout: 1 2 3 / 4 5 6 / 7 8 9 / ⌫ 0 (blank)
        let rows: [[KeypadKey]] = [
            [.digit(1), .digit(2), .digit(3)],
            [.digit(4), .digit(5), .digit(6)],
            [.digit(7), .digit(8), .digit(9)],
            [.backspace, .digit(0), .blank]
        ]
        for row in rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.alignment = .fill
            rowStack.distribution = .fillEqually
            rowStack.spacing = 8
            for key in row {
                rowStack.addArrangedSubview(makeKeyButton(for: key))
            }
            keypadStack.addArrangedSubview(rowStack)
        }
    }

    private func makeKeyButton(for key: KeypadKey) -> UIView {
        switch key {
        case .blank:
            let spacer = UIView()
            spacer.backgroundColor = .clear
            return spacer
        case .digit(let value):
            let button = UIButton(type: .system)
            button.setTitle("\(value)", for: .normal)
            button.titleLabel?.font = SkyFonts.headline(22)
            button.setTitleColor(SkyColors.onSurface, for: .normal)
            button.backgroundColor = SkyColors.surfaceContainerLow
            button.layer.cornerRadius = 14
            button.layer.cornerCurve = .continuous
            button.tag = value
            button.addTarget(self, action: #selector(handleDigitTapped(_:)), for: .touchUpInside)
            return button
        case .backspace:
            let button = UIButton(type: .system)
            button.setTitle("⌫", for: .normal)
            button.titleLabel?.font = SkyFonts.headline(20)
            button.setTitleColor(SkyColors.onSurfaceVariant, for: .normal)
            button.backgroundColor = SkyColors.surfaceContainerLow
            button.layer.cornerRadius = 14
            button.layer.cornerCurve = .continuous
            button.addTarget(self, action: #selector(handleBackspace), for: .touchUpInside)
            return button
        }
    }

    private func buildLayout() {
        let keypadHeight: CGFloat = 4 * 52 + 3 * 8 // 4 rows of 52pt with 8pt spacing.

        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 340),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            instructionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            instructionLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            questionLabel.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 18),
            questionLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            questionLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            inputDisplay.topAnchor.constraint(equalTo: questionLabel.bottomAnchor, constant: 14),
            inputDisplay.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            inputDisplay.widthAnchor.constraint(equalToConstant: 180),
            inputDisplay.heightAnchor.constraint(equalToConstant: 52),

            errorLabel.topAnchor.constraint(equalTo: inputDisplay.bottomAnchor, constant: 6),
            errorLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            errorLabel.heightAnchor.constraint(equalToConstant: 18),

            keypadStack.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 12),
            keypadStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            keypadStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            keypadStack.heightAnchor.constraint(equalToConstant: keypadHeight),

            checkButton.topAnchor.constraint(equalTo: keypadStack.bottomAnchor, constant: 14),
            checkButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            checkButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            checkButton.heightAnchor.constraint(equalToConstant: 50),

            holdButton.topAnchor.constraint(equalTo: questionLabel.bottomAnchor, constant: 32),
            holdButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            holdButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            holdButton.heightAnchor.constraint(equalToConstant: 64),

            holdProgressFill.leadingAnchor.constraint(equalTo: holdButton.leadingAnchor),
            holdProgressFill.topAnchor.constraint(equalTo: holdButton.topAnchor),
            holdProgressFill.bottomAnchor.constraint(equalTo: holdButton.bottomAnchor),

            holdLabel.centerXAnchor.constraint(equalTo: holdButton.centerXAnchor),
            holdLabel.centerYAnchor.constraint(equalTo: holdButton.centerYAnchor),

            holdHintLabel.topAnchor.constraint(equalTo: holdButton.bottomAnchor, constant: 10),
            holdHintLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            holdHintLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            holdHintLabel.heightAnchor.constraint(equalToConstant: 18),

            cancelButton.topAnchor.constraint(equalTo: checkButton.bottomAnchor, constant: 10),
            cancelButton.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            cancelButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        let fillWidth = holdProgressFill.widthAnchor.constraint(equalToConstant: 0)
        fillWidth.isActive = true
        holdProgressWidth = fillWidth
    }

    private func buildStyle() {
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.55)

        card.backgroundColor = SkyColors.surfaceContainerLowest
        card.layer.cornerRadius = 24
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = SkyColors.onSurface.cgColor
        card.layer.shadowOpacity = 0.18
        card.layer.shadowRadius = 28
        card.layer.shadowOffset = CGSize(width: 0, height: 14)

        titleLabel.text = "This area is for parents only."
        titleLabel.font = SkyFonts.body(13, medium: true)
        titleLabel.textColor = SkyColors.onSurfaceVariant
        titleLabel.textAlignment = .center

        instructionLabel.text = "Please solve the problem below to continue."
        instructionLabel.font = SkyFonts.body(13)
        instructionLabel.textColor = SkyColors.onSurfaceVariant
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 2

        questionLabel.font = SkyFonts.headline(28)
        questionLabel.textColor = SkyColors.primary
        questionLabel.textAlignment = .center
        questionLabel.numberOfLines = 1
        questionLabel.adjustsFontSizeToFitWidth = true
        questionLabel.minimumScaleFactor = 0.7

        inputDisplay.backgroundColor = SkyColors.surfaceContainerLow
        inputDisplay.layer.cornerRadius = 12
        inputDisplay.layer.cornerCurve = .continuous
        inputDisplay.textAlignment = .center
        inputDisplay.font = SkyFonts.headline(28)
        inputDisplay.textColor = SkyColors.onSurface
        inputDisplay.text = " "

        errorLabel.font = SkyFonts.body(13)
        errorLabel.textColor = UIColor(hex: 0xC0392B)
        errorLabel.textAlignment = .center
        errorLabel.text = " "

        checkButton.setTitle("Check Answer", for: .normal)
        checkButton.titleLabel?.font = SkyFonts.headline(18)
        checkButton.setTitleColor(SkyColors.onPrimary, for: .normal)
        checkButton.backgroundColor = SkyColors.primary
        checkButton.layer.cornerRadius = 24
        checkButton.layer.cornerCurve = .continuous
        checkButton.addTarget(self, action: #selector(handleCheckAnswer), for: .touchUpInside)
        checkButton.isEnabled = false
        checkButton.alpha = 0.5

        holdButton.backgroundColor = SkyColors.surfaceContainer
        holdButton.layer.cornerRadius = 24
        holdButton.layer.cornerCurve = .continuous
        holdButton.layer.masksToBounds = true
        holdButton.addTarget(self, action: #selector(holdTouchDown), for: .touchDown)
        holdButton.addTarget(self, action: #selector(holdTouchEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])

        holdProgressFill.backgroundColor = SkyColors.primary
        holdProgressFill.isUserInteractionEnabled = false

        holdLabel.text = "Hold to Unlock"
        holdLabel.font = SkyFonts.headline(18)
        holdLabel.textColor = SkyColors.onPrimary
        holdLabel.isUserInteractionEnabled = false

        holdHintLabel.text = " "
        holdHintLabel.font = SkyFonts.body(13)
        holdHintLabel.textColor = SkyColors.onSurfaceVariant
        holdHintLabel.textAlignment = .center

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = SkyFonts.body(14, medium: true)
        cancelButton.setTitleColor(SkyColors.onSurfaceVariant, for: .normal)
        cancelButton.addTarget(self, action: #selector(handleCancel), for: .touchUpInside)
    }

    // MARK: - Layer transitions

    private func showMathLayer() {
        questionLabel.isHidden = false
        inputDisplay.isHidden = false
        errorLabel.isHidden = false
        keypadStack.isHidden = false
        checkButton.isHidden = false

        holdButton.isHidden = true
        holdHintLabel.isHidden = true
        instructionLabel.text = "Please solve the problem below to continue."
    }

    private func showHoldLayer() {
        questionLabel.isHidden = true
        inputDisplay.isHidden = true
        errorLabel.isHidden = true
        keypadStack.isHidden = true
        checkButton.isHidden = true

        holdButton.isHidden = false
        holdHintLabel.isHidden = false
        instructionLabel.text = "One last step — press and hold the button below."
    }

    // MARK: - Problem generation

    private func regenerateProblem() {
        // Constraints: A,B in 6...9, C in 10...25, result in 30...100,
        // and not previously seen this session. Bounded retry — combinatorics
        // are small so we cap attempts to avoid any pathological loop.
        for _ in 0..<200 {
            let a = Int.random(in: 6...9)
            let b = Int.random(in: 6...9)
            let c = Int.random(in: 10...25)
            let plus = Bool.random()
            let result = plus ? (a * b + c) : (a * b - c)
            guard result >= 30 && result <= 100 else { continue }
            let key = "\(a)x\(b)\(plus ? "+" : "-")\(c)"
            if Self.seenProblems.contains(key) { continue }
            Self.seenProblems.insert(key)
            commit(a: a, b: b, c: c, plus: plus, answer: result)
            return
        }
        // All combinations have been exhausted in this session — clear and
        // pick a fresh problem so the gate remains usable.
        Self.seenProblems.removeAll()
        let a = Int.random(in: 6...9)
        let b = Int.random(in: 6...9)
        let c = Int.random(in: 10...25)
        let plus = (a * b - c) < 30 ? true : Bool.random()
        let result = plus ? (a * b + c) : (a * b - c)
        Self.seenProblems.insert("\(a)x\(b)\(plus ? "+" : "-")\(c)")
        commit(a: a, b: b, c: c, plus: plus, answer: result)
    }

    private func commit(a: Int, b: Int, c: Int, plus: Bool, answer: Int) {
        operandA = a
        operandB = b
        operandC = c
        usesPlus = plus
        expectedAnswer = answer
        let op = plus ? "+" : "−"
        questionLabel.text = "What is \(a) × \(b) \(op) \(c)?"
    }

    // MARK: - Input display

    private func refreshInputDisplay() {
        inputDisplay.text = enteredText.isEmpty ? " " : enteredText
        let enabled = !enteredText.isEmpty
        checkButton.isEnabled = enabled
        checkButton.alpha = enabled ? 1.0 : 0.5
        // Any new input dismisses the previous error.
        if errorLabel.text != " " {
            errorLabel.text = " "
        }
    }

    // MARK: - Keypad actions

    @objc private func handleDigitTapped(_ sender: UIButton) {
        guard enteredText.count < Self.maxInputLength else { return }
        enteredText.append("\(sender.tag)")
    }

    @objc private func handleBackspace() {
        guard !enteredText.isEmpty else { return }
        enteredText.removeLast()
    }

    @objc private func handleCheckAnswer() {
        guard let entered = Int(enteredText) else { return }
        if entered == expectedAnswer {
            mathPassed = true
            enteredText = ""
            errorLabel.text = " "
            showHoldLayer()
        } else {
            errorLabel.text = "That's not right. Try again."
            enteredText = ""
            shakeCard()
        }
    }

    private func shakeCard() {
        UIView.animate(withDuration: 0.07, animations: {
            self.card.transform = CGAffineTransform(translationX: -8, y: 0)
        }, completion: { _ in
            UIView.animate(withDuration: 0.07, animations: {
                self.card.transform = CGAffineTransform(translationX: 8, y: 0)
            }, completion: { _ in
                UIView.animate(withDuration: 0.07) {
                    self.card.transform = .identity
                }
            })
        })
    }

    // MARK: - Hold-to-unlock

    @objc private func holdTouchDown() {
        guard mathPassed else { return }
        invalidateHoldTimer()
        holdStart = CACurrentMediaTime()
        holdHintLabel.text = "Keep holding to confirm."
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tickHold()
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    @objc private func holdTouchEnded() {
        guard mathPassed else { return }
        if holdProgress >= 1.0 { return } // Completion already handled.
        invalidateHoldTimer()
        holdProgress = 0.0
        applyHoldProgress()
        holdHintLabel.text = " "
    }

    private func tickHold() {
        let elapsed = CACurrentMediaTime() - holdStart
        let progress = min(1.0, elapsed / Self.holdDuration)
        holdProgress = progress
        applyHoldProgress()
        if progress >= 1.0 {
            invalidateHoldTimer()
            completeHold()
        }
    }

    private func applyHoldProgress() {
        let width = holdButton.bounds.width * CGFloat(holdProgress)
        holdProgressWidth?.constant = width
        holdButton.layoutIfNeeded()
    }

    private func invalidateHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func completeHold() {
        let completion = onGatePassedCompletion
        dismiss(animated: true) {
            completion?()
        }
    }

    // MARK: - Cancel

    @objc private func handleCancel() {
        invalidateHoldTimer()
        let completion = onCancel
        dismiss(animated: true) {
            completion?()
        }
    }
}

// MARK: - Helpers

private enum KeypadKey {
    case digit(Int)
    case backspace
    case blank
}
