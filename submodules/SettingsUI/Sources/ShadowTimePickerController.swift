import Foundation
import UIKit

// Shadow: a small sheet with a time wheel (hours and minutes) for settings
// such as the «Тихая отправка» schedule. `minute` is minutes after midnight;
// «Готово» returns the picked one, «Отмена» or a swipe down returns nothing.
final class ShadowTimePickerController: UIViewController {
    private let titleText: String
    private let initialMinute: Int32
    private let completion: (Int32) -> Void
    private let picker = UIDatePicker()

    init(title: String, minute: Int32, completion: @escaping (Int32) -> Void) {
        self.titleText = title
        self.initialMinute = minute
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *), let sheet = self.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = self.titleText
        titleLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        titleLabel.textAlignment = .center

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Отмена", for: .normal)
        cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0)
        cancelButton.addTarget(self, action: #selector(self.cancelPressed), for: .touchUpInside)

        let doneButton = UIButton(type: .system)
        doneButton.setTitle("Готово", for: .normal)
        doneButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        doneButton.addTarget(self, action: #selector(self.donePressed), for: .touchUpInside)

        self.picker.datePickerMode = .time
        if #available(iOS 13.4, *) {
            self.picker.preferredDatePickerStyle = .wheels
        }
        self.picker.locale = Locale(identifier: "ru_RU")
        self.picker.minuteInterval = 5
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let midnight = calendar.startOfDay(for: Date())
        self.picker.date = midnight.addingTimeInterval(TimeInterval(self.initialMinute) * 60.0)

        for subview in [titleLabel, cancelButton, doneButton, self.picker] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 22.0),
            titleLabel.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            cancelButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            cancelButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16.0),
            doneButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            doneButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16.0),
            self.picker.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16.0),
            self.picker.centerXAnchor.constraint(equalTo: self.view.centerXAnchor)
        ])
    }

    @objc private func cancelPressed() {
        self.dismiss(animated: true)
    }

    @objc private func donePressed() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: self.picker.date)
        let minute = Int32((components.hour ?? 0) * 60 + (components.minute ?? 0))
        self.dismiss(animated: true)
        self.completion(minute)
    }
}
