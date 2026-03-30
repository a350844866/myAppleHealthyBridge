import Foundation
import HealthKit

@MainActor
final class SyncStore: ObservableObject {
    @Published private(set) var settings: SyncSettings
    @Published private(set) var lastSyncResult: SyncRunResult?
    @Published private(set) var healthAuthorizationState: HealthAuthorizationState
    @Published private(set) var observerRuntimeState: ObserverRuntimeState

    private let defaults: UserDefaults
    private let settingsKey = "sync.settings"
    private let resultKey = "sync.lastResult"
    private let healthAuthorizationKey = "health.authorization"
    private let observerRuntimeKey = "sync.observerRuntime"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if
            let data = defaults.data(forKey: settingsKey),
            let settings = try? JSONDecoder().decode(SyncSettings.self, from: data)
        {
            self.settings = settings
        } else {
            self.settings = .default
        }

        if
            let data = defaults.data(forKey: resultKey),
            let result = try? JSONDecoder().decode(SyncRunResult.self, from: data)
        {
            self.lastSyncResult = result
        } else {
            self.lastSyncResult = nil
        }

        if
            let data = defaults.data(forKey: healthAuthorizationKey),
            let state = try? JSONDecoder().decode(HealthAuthorizationState.self, from: data)
        {
            self.healthAuthorizationState = state
        } else {
            self.healthAuthorizationState = .default
        }

        if
            let data = defaults.data(forKey: observerRuntimeKey),
            let state = try? JSONDecoder().decode(ObserverRuntimeState.self, from: data)
        {
            self.observerRuntimeState = state
        } else {
            self.observerRuntimeState = .default
        }
    }

    func updateSettings(baseURLString: String, apiToken: String, deviceID: String, autoSyncEnabled: Bool) {
        settings = SyncSettings(
            baseURLString: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines),
            apiToken: apiToken.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceID: deviceID.trimmingCharacters(in: .whitespacesAndNewlines),
            autoSyncEnabled: autoSyncEnabled
        )
        persist(settings, forKey: settingsKey)
    }

    func record(result: SyncRunResult) {
        lastSyncResult = result
        persist(result, forKey: resultKey)
    }

    func recordHealthAuthorizationRequested(success: Bool) {
        healthAuthorizationState = HealthAuthorizationState(
            hasRequestedAccess: true,
            lastRequestSucceeded: success
        )
        persist(healthAuthorizationState, forKey: healthAuthorizationKey)
    }

    func recordObserverState(
        isEnabled: Bool,
        observedTypeCount: Int,
        lastTriggerAt: Date? = nil,
        lastTriggerType: String? = nil,
        lastErrorMessage: String? = nil
    ) {
        observerRuntimeState = ObserverRuntimeState(
            isEnabled: isEnabled,
            observedTypeCount: observedTypeCount,
            lastTriggerAt: lastTriggerAt ?? observerRuntimeState.lastTriggerAt,
            lastTriggerType: lastTriggerType ?? observerRuntimeState.lastTriggerType,
            lastErrorMessage: lastErrorMessage
        )
        persist(observerRuntimeState, forKey: observerRuntimeKey)
    }

    func anchor(for identifier: String) -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: anchorKey(for: identifier)) else {
            return nil
        }

        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    func save(anchor: HKQueryAnchor, for identifier: String) throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        defaults.set(data, forKey: anchorKey(for: identifier))
    }

    func encodedAnchors(for identifiers: [String]) -> [String: String] {
        identifiers.reduce(into: [String: String]()) { partialResult, identifier in
            guard let data = defaults.data(forKey: anchorKey(for: identifier)) else {
                return
            }

            partialResult[identifier] = data.base64EncodedString()
        }
    }

    func encodedString(for anchor: HKQueryAnchor) throws -> String {
        let data = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        return data.base64EncodedString()
    }

    private func anchorKey(for identifier: String) -> String {
        "sync.anchor.\(identifier)"
    }

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
