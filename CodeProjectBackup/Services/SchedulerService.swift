import Foundation

@MainActor
final class SchedulerService: ObservableObject {
    static let shared = SchedulerService()

    private let settings = SettingsStore.shared
    private let runManager = RunManager.shared
    private var timer: Timer?

    func start() {
        stop()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkDue()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        checkDue()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func checkDue() {
        guard !runManager.isRunning else { return }
        switch settings.scheduleMode {
        case .manual:
            return
        case .hourly:
            if let last = settings.lastScheduledRun {
                guard Date().timeIntervalSince(last) >= 3600 else { return }
            }
            trigger()
        case .daily, .weekly:
            guard let slot = mostRecentSlot() else { return }
            if let last = settings.lastScheduledRun, last >= slot { return }
            if Date() >= slot {
                trigger()
            }
        }
    }

    private func mostRecentSlot() -> Date? {
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = settings.scheduleHour
        components.minute = settings.scheduleMinute
        switch settings.scheduleMode {
        case .daily:
            break
        case .weekly:
            components.weekday = settings.scheduleWeekday
        default:
            return nil
        }
        return calendar.nextDate(
            after: Date(),
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .backward
        )
    }

    private func trigger() {
        settings.lastScheduledRun = Date()
        let config = settings.makeRunConfiguration()
        runManager.run(config: config)
    }
}
