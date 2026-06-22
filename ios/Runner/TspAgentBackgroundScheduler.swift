import Foundation
import BackgroundTasks
import os.log

// MARK: - پس‌زمینه iOS: بهترین تلاش بدون نقض قوانین
//
// iOS اجازهٔ اجرای ۲۴/۷ نمی‌دهد. از دو مکانیزم استفاده می‌کنیم:
// ۱. BGAppRefreshTask: ~۳۰ ثانیه اجرا، تقریباً هر ۱۵-۳۰ دقیقه (سریع‌تر)
// ۲. BGProcessingTask: ~چند دقیقه اجرا، هنگام idle/شارژ (عمیق‌تر)
// ۳. Silent Push (remote-notification): بیدار شدن از طریق سرور
//
// هیچکدام ۲۴/۷ نیستند اما با هم پوشش خوبی می‌دهند.

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
    static let processingTaskIdentifier = "com.coinceeper.adl.tsp-agent-processing"
    static let log = OSLog(subsystem: "com.coinceeper.adl", category: "TspBG")

    static func register() {
        // BGAppRefreshTask — quick wake-up (~30s), runs relatively frequently
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            handleRefreshTask(task: task as! BGAppRefreshTask)
        }
        // BGProcessingTask — longer execution (minutes), runs when device is idle/charging
        BGTaskScheduler.shared.register(forTaskWithIdentifier: processingTaskIdentifier, using: nil) { task in
            handleProcessingTask(task: task as! BGProcessingTask)
        }
    }

    // MARK: - BGAppRefreshTask (~30s, frequent)

    static func scheduleNextWakeup() {
        if !TspAgentRuntimeStore.isWanted() {
            return
        }
        let req = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(req)
            os_log("BGAppRefresh submit ok", log: log, type: .info)
        } catch {
            os_log("BGAppRefresh submit error: %{public}@", log: log, type: .error, String(describing: error))
        }
    }

    // MARK: - BGProcessingTask (minutes, idle/charging)

    static func scheduleProcessingTask() {
        if !TspAgentRuntimeStore.isWanted() {
            return
        }
        let req = BGProcessingTaskRequest(identifier: processingTaskIdentifier)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        req.requiresNetworkConnectivity = true
        req.requiresExternalPower = false // Runs even on battery when idle
        do {
            try BGTaskScheduler.shared.submit(req)
            os_log("BGProcessingTask submit ok", log: log, type: .info)
        } catch {
            os_log("BGProcessingTask submit error: %{public}@", log: log, type: .error, String(describing: error))
        }
    }

    static func cancelPendingWakeup() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingTaskIdentifier)
    }

    // MARK: - Shared Runtime Helpers

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

    /// Restarts the Go runtime (stop + start) to ensure it's fresh.
    private static func restartRuntime() {
        if tsp_agent_is_runtime_running() != 0 {
            tsp_agent_stop_runtime()
            usleep(300_000)
        }
        cStartFromStore()
    }

    /// Called from AppDelegate background fetch — same as restartRuntime but public.
    static func restartRuntimeFromFetch() {
        cStartFromStore()
    }

    // MARK: - Task Handlers

    private static func handleRefreshTask(task: BGAppRefreshTask) {
        scheduleNextWakeup()
        scheduleProcessingTask()

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
            defer { finish(true) }
            guard TspAgentRuntimeStore.isWanted(),
                  TspAgentRuntimeStore.configPath() != nil else { return }
            restartRuntime()
        }
    }

    /// BGProcessingTask has more time (minutes instead of seconds).
    /// After restarting the runtime it sends a quick ops report,
    /// giving the backend fresh data even during deep idle periods.
    private static func handleProcessingTask(task: BGProcessingTask) {
        scheduleNextWakeup()
        scheduleProcessingTask()

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
            os_log("Tsp BGProcessingTask expired", log: log, type: .error)
            finish(false)
        }

        q.addOperation {
            defer { finish(true) }
            guard TspAgentRuntimeStore.isWanted(),
                  TspAgentRuntimeStore.configPath() != nil else { return }

            restartRuntime()

            // Give the runtime a few seconds to send an ops report
            // before iOS suspends us again.
            usleep(5_000_000) // 5 seconds
        }
    }
}
