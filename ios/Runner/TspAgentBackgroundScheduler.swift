import Foundation
import BackgroundTasks
import os.log

// MARK: - پس‌زمینه iOS: بهترین تلاش بدون نقض قوانین
//
// اجرای نامحدود ۲۴/۷ بدون سناریوهای مجاز (مثلاً حالت‌های UIBackgroundModes مرتبط) تضمین نمی‌شود.
// BGAppRefresh بهترین «تلاش مجاز» است: اجراها کوتاه و زمانبندی کاملاً تحت کنترل سیستم.
// اگر باید مرتبا بیدار شوید: Remote Notifications / PushKit (در صورت توجیه دقیق محصول) را جدا بررسی کنید.

enum TspAgentRuntimeStore {
    static let kConfig = "tsp_ios_config_path"
    static let kState = "tsp_ios_state_path"
    static let kWants = "tsp_ios_bg_agent_enabled"

    static func save(configPath: String, statePath: String?) {
        let d = UserDefaults.standard
        d.set(configPath, forKey: kConfig)
        if let s = statePath, !s.isEmpty {
            d.set(s, forKey: kState)
        } else {
            d.removeObject(forKey: kState)
        }
        d.set(true, forKey: kWants)
    }

    static func clear() {
        let d = UserDefaults.standard
        d.removeObject(forKey: kConfig)
        d.removeObject(forKey: kState)
        d.set(false, forKey: kWants)
    }

    static func isWanted() -> Bool {
        UserDefaults.standard.bool(forKey: kWants)
    }

    static func configPath() -> String? {
        let s = UserDefaults.standard.string(forKey: kConfig)
        if s == nil || s?.isEmpty == true { return nil }
        return s
    }

    static func statePath() -> String? {
        UserDefaults.standard.string(forKey: kState)
    }
}

enum TspAgentBackgroundScheduler {
    /// باید با Info.plist (BGTaskSchedulerPermittedIdentifiers) منطبق باشد
    static let taskIdentifier = "com.coinceeper.adl.tsp-agent-refresh"
    private static let log = OSLog(subsystem: "com.coinceeper.adl", category: "TspBG")

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            handleRefreshTask(task: task as! BGAppRefreshTask)
        }
    }

    static func scheduleNextWakeup() {
        if !TspAgentRuntimeStore.isWanted() {
            return
        }
        let req = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // earliestBeginDate حدودِ قابل اعلام است — فاصلهٔ اجرا را سیستم تعیین می‌کند
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(req)
            os_log("BGAppRefresh submit ok", log: log, type: .info)
        } catch {
            os_log("BGAppRefresh submit error: %{public}@", log: log, type: .error, String(describing: error))
        }
    }

    static func cancelPendingWakeup() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    private static func cStartFromStore() {
        guard let cPath = TspAgentRuntimeStore.configPath() else { return }
        AppDelegate.applyTspAgentRaspBypassForEmbeddedRuntimeIfNeeded()
        cPath.withCString { pCfg in
            if let s = TspAgentRuntimeStore.statePath(), !s.isEmpty {
                s.withCString { pSt in
                    _ = tsp_agent_start_paths(pCfg, pSt)
                }
            } else {
                _ = tsp_agent_start_paths(pCfg, nil)
            }
        }
    }

    private static func handleRefreshTask(task: BGAppRefreshTask) {
        scheduleNextWakeup()

        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        var completed = false
        let lock = NSLock()
        let finish: (Bool) -> Void = { success in
            lock.lock()
            if !completed {
                completed = true
                task.setTaskCompleted(success: success)
            }
            lock.unlock()
        }

        task.expirationHandler = {
            q.cancelAllOperations()
            os_log("Tsp BGAppRefresh expired", log: log, type: .error)
            finish(false)
        }

        q.addOperation {
            if !TspAgentRuntimeStore.isWanted() {
                finish(true)
                return
            }
            if TspAgentRuntimeStore.configPath() == nil {
                finish(true)
                return
            }
            if tsp_agent_is_runtime_running() == 0 {
                cStartFromStore()
            } else {
                tsp_agent_stop_runtime()
                usleep(300_000)
                cStartFromStore()
            }
            finish(true)
        }
    }
}
