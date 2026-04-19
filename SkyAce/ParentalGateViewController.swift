import UIKit

/// Apple Kids category parental gate.
///
/// Rules:
///   - Random multiplication with operands in 4...9.
///   - On a wrong answer the text field is cleared AND a new problem is
///     generated so no-one can brute-force the same question.
///   - The Cancel button invokes `onCancel` (defaulted to a no-op dismiss).
///   - The Verify button runs `onSuccess` only on a correct answer.
final class ParentalGateViewController: UIViewController {

    var onSuccess: () -> Void = {}
    var onCancel:  () -> Void = {}

    // MARK: - State
    private var numberA: Int = 0
    private var numberB: Int = 0
    private var expectedAnswer: Int { return numberA * numberB }

    // MARK: - Views
    private let dimView         = UIView()
    private let card            = UIView()
    private let titleLabel      = UILabel()
    private let instructionLabel = UILabel()
    private let questionLabel   = UILabel()
    private let answerField     = UITextField()
    private let errorLabel      = UILabel()
    private let verifyButton    = UIButton(type: .system)
    private let cancelButton    = UIButton(type: .system)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildHierarchy()
        buildLayout()
        buildStyle()
        regenerateProblem()
        answerField.becomeFirstResponder()
    }

    // MARK: - Build

    private func buildHierarchy() {
        dimView.translatesAutoresizingMaskIntoConstraints = false
        card.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        questionLabel.translatesAutoresizingMaskIntoConstraints = false
        answerField.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        verifyButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(dimView)
        view.addSubview(card)
        card.addSubview(titleLabel)
        card.addSubview(instructionLabel)
        card.addSubview(questionLabel)
        card.addSubview(answerField)
        card.addSubview(errorLabel)
        card.addSubview(verifyButton)
        card.addSubview(cancelButton)
    }

    private func buildLayout() {
        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -60),
            card.widthAnchor.constraint(equalToConstant: 320),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            instructionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            instructionLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            questionLabel.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 20),
            questionLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            questionLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            answerField.topAnchor.constraint(equalTo: questionLabel.bottomAnchor, constant: 16),
            answerField.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            answerField.widthAnchor.constraint(equalToConstant: 160),
            answerField.heightAnchor.constraint(equalToConstant: 48),

            errorLabel.topAnchor.constraint(equalTo: answerField.bottomAnchor, constant: 8),
            errorLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            errorLabel.heightAnchor.constraint(equalToConstant: 18),

            verifyButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 16),
            verifyButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            verifyButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            verifyButton.heightAnchor.constraint(equalToConstant: 48),

            cancelButton.topAnchor.constraint(equalTo: verifyButton.bottomAnchor, constant: 8),
            cancelButton.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            cancelButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func buildStyle() {
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.45)

        card.backgroundColor = SkyColors.surfaceContainerLowest
        card.layer.cornerRadius = 24
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = SkyColors.onSurface.cgColor
        card.layer.shadowOpacity = 0.12
        card.layer.shadowRadius = 24
        card.layer.shadowOffset = CGSize(width: 0, height: 12)

        titleLabel.text = "Parent Zone"
        titleLabel.font = SkyFonts.headline(24)
        titleLabel.textColor = SkyColors.onSurface
        titleLabel.textAlignment = .center

        instructionLabel.text = "Ask a grown-up to solve this before continuing."
        instructionLabel.font = SkyFonts.body(14)
        instructionLabel.textColor = SkyColors.onSurfaceVariant
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 2

        questionLabel.font = SkyFonts.headline(32)
        questionLabel.textColor = SkyColors.primary
        questionLabel.textAlignment = .center

        answerField.borderStyle = .none
        answerField.backgroundColor = SkyColors.surfaceContainerLow
        answerField.layer.cornerRadius = 12
        answerField.layer.cornerCurve = .continuous
        answerField.textAlignment = .center
        answerField.font = SkyFonts.headline(26)
        answerField.textColor = SkyColors.onSurface
        answerField.keyboardType = .numberPad
        answerField.returnKeyType = .done
        answerField.addTarget(self, action: #selector(handleAnswerChanged), for: .editingChanged)

        errorLabel.font = SkyFonts.body(13)
        errorLabel.textColor = UIColor(hex: 0xC0392B)
        errorLabel.textAlignment = .center
        errorLabel.text = " "

        styleVerifyButton()
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = SkyFonts.body(14, medium: true)
        cancelButton.setTitleColor(SkyColors.onSurfaceVariant, for: .normal)
        cancelButton.addTarget(self, action: #selector(handleCancel), for: .touchUpInside)

        verifyButton.addTarget(self, action: #selector(handleVerify), for: .touchUpInside)
    }

    private func styleVerifyButton() {
        verifyButton.setTitle("Verify", for: .normal)
        verifyButton.titleLabel?.font = SkyFonts.headline(18)
        verifyButton.setTitleColor(SkyColors.onPrimary, for: .normal)
        verifyButton.backgroundColor = SkyColors.primary
        verifyButton.layer.cornerRadius = 24
        verifyButton.layer.cornerCurve = .continuous
    }

    // MARK: - Problem

    private func regenerateProblem() {
        numberA = Int.random(in: 4...9)
        numberB = Int.random(in: 4...9)
        questionLabel.text = "\(numberA)  ×  \(numberB)  =  ?"
        answerField.text = ""
        errorLabel.text = " "
    }

    // MARK: - Actions

    @objc private func handleAnswerChanged() {
        errorLabel.text = " "
    }

    @objc private func handleVerify() {
        guard let text = answerField.text, let entered = Int(text) else {
            errorLabel.text = "Please enter a number."
            return
        }
        if entered == expectedAnswer {
            answerField.resignFirstResponder()
            onSuccess()
        } else {
            // Regenerate to prevent brute-force on the same question.
            errorLabel.text = "Not quite — try the new one."
            regenerateProblem()
            UIView.animate(withDuration: 0.08, animations: {
                self.card.transform = CGAffineTransform(translationX: -8, y: 0)
            }, completion: { _ in
                UIView.animate(withDuration: 0.08) {
                    self.card.transform = CGAffineTransform(translationX: 8, y: 0)
                } completion: { _ in
                    UIView.animate(withDuration: 0.08) {
                        self.card.transform = .identity
                    }
                }
            })
        }
    }

    @objc private func handleCancel() {
        answerField.resignFirstResponder()
        dismiss(animated: true) {
            self.onCancel()
        }
    }
}
