import Foundation
import HealthKit

struct AnchoredSamplesResult {
    let samples: [IngestItem]
    let newAnchor: HKQueryAnchor?
    let reachedQueryLimit: Bool
}

struct AnchoredFetchBatchResult {
    let results: [String: AnchoredSamplesResult]
    let reachedSyncLimit: Bool
}

final class HealthKitManager {
    private struct QuantityTypeSpec {
        let identifier: String
        let unit: HKUnit
    }

    private struct CategoryTypeSpec {
        let identifier: String
    }

    private let store = HKHealthStore()
    private var observerQueries: [String: HKObserverQuery] = [:]

    private let quantityTypeSpecs: [QuantityTypeSpec] = [
        .init(identifier: "HKQuantityTypeIdentifierHeartRate", unit: HKUnit.count().unitDivided(by: .minute())),
        .init(identifier: "HKQuantityTypeIdentifierOxygenSaturation", unit: HKUnit.percent()),
        .init(identifier: "HKQuantityTypeIdentifierRespiratoryRate", unit: HKUnit.count().unitDivided(by: .minute())),
        .init(identifier: "HKQuantityTypeIdentifierStepCount", unit: HKUnit.count()),
        .init(identifier: "HKQuantityTypeIdentifierActiveEnergyBurned", unit: .kilocalorie()),
        .init(identifier: "HKQuantityTypeIdentifierBasalEnergyBurned", unit: .kilocalorie()),
        .init(identifier: "HKQuantityTypeIdentifierPhysicalEffort", unit: HKUnit(from: "kcal/hr·kg")),
        .init(identifier: "HKQuantityTypeIdentifierDistanceWalkingRunning", unit: .meter()),
        .init(identifier: "HKQuantityTypeIdentifierWalkingSpeed", unit: HKUnit.meter().unitDivided(by: .second())),
        .init(identifier: "HKQuantityTypeIdentifierStairAscentSpeed", unit: HKUnit.meter().unitDivided(by: .second())),
        .init(identifier: "HKQuantityTypeIdentifierStairDescentSpeed", unit: HKUnit.meter().unitDivided(by: .second())),
        .init(identifier: "HKQuantityTypeIdentifierAppleExerciseTime", unit: .minute()),
        .init(identifier: "HKQuantityTypeIdentifierAppleStandTime", unit: .minute()),
        .init(identifier: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN", unit: .secondUnit(with: .milli)),
        .init(identifier: "HKQuantityTypeIdentifierRestingHeartRate", unit: HKUnit.count().unitDivided(by: .minute())),
        .init(identifier: "HKQuantityTypeIdentifierWalkingHeartRateAverage", unit: HKUnit.count().unitDivided(by: .minute())),
        .init(identifier: "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute", unit: HKUnit.count().unitDivided(by: .minute())),
        .init(identifier: "HKQuantityTypeIdentifierFlightsClimbed", unit: .count()),
        .init(identifier: "HKQuantityTypeIdentifierDistanceCycling", unit: .meter()),
        .init(identifier: "HKQuantityTypeIdentifierDistanceSwimming", unit: .meter()),
        .init(identifier: "HKQuantityTypeIdentifierDistanceWheelchair", unit: .meter()),
        .init(identifier: "HKQuantityTypeIdentifierDistanceDownhillSnowSports", unit: .meter()),
        .init(identifier: "HKQuantityTypeIdentifierWalkingStepLength", unit: .meter()),
        .init(identifier: "HKQuantityTypeIdentifierSixMinuteWalkTestDistance", unit: .meter()),
        .init(identifier: "HKQuantityTypeIdentifierRunningSpeed", unit: HKUnit.meter().unitDivided(by: .second())),
        .init(identifier: "HKQuantityTypeIdentifierRunningStrideLength", unit: .meter()),
        .init(identifier: "HKQuantityTypeIdentifierRunningPower", unit: .watt()),
        .init(identifier: "HKQuantityTypeIdentifierRunningGroundContactTime", unit: .secondUnit(with: .milli)),
        .init(identifier: "HKQuantityTypeIdentifierRunningVerticalOscillation", unit: .meterUnit(with: .milli)),
        .init(identifier: "HKQuantityTypeIdentifierSwimmingStrokeCount", unit: .count()),
        .init(identifier: "HKQuantityTypeIdentifierPushCount", unit: .count()),
        .init(identifier: "HKQuantityTypeIdentifierEnvironmentalAudioExposure", unit: .decibelAWeightedSoundPressureLevel()),
        .init(identifier: "HKQuantityTypeIdentifierEnvironmentalSoundReduction", unit: .decibelAWeightedSoundPressureLevel()),
        .init(identifier: "HKQuantityTypeIdentifierHeadphoneAudioExposure", unit: .decibelAWeightedSoundPressureLevel()),
        .init(identifier: "HKQuantityTypeIdentifierBodyMass", unit: .gramUnit(with: .kilo)),
        .init(identifier: "HKQuantityTypeIdentifierBodyMassIndex", unit: .count()),
        .init(identifier: "HKQuantityTypeIdentifierLeanBodyMass", unit: .gramUnit(with: .kilo)),
        .init(identifier: "HKQuantityTypeIdentifierHeight", unit: .meter()),
        .init(identifier: "HKQuantityTypeIdentifierBodyFatPercentage", unit: .percent()),
        .init(identifier: "HKQuantityTypeIdentifierVO2Max", unit: HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .minute())),
        .init(identifier: "HKQuantityTypeIdentifierTimeInDaylight", unit: .minute()),
        .init(identifier: "HKQuantityTypeIdentifierWalkingAsymmetryPercentage", unit: .percent()),
        .init(identifier: "HKQuantityTypeIdentifierWalkingDoubleSupportPercentage", unit: .percent()),
        .init(identifier: "HKQuantityTypeIdentifierAppleWalkingSteadiness", unit: .percent()),
        .init(identifier: "HKQuantityTypeIdentifierAtrialFibrillationBurden", unit: .percent()),
        .init(identifier: "HKQuantityTypeIdentifierBodyTemperature", unit: .degreeCelsius()),
        .init(identifier: "HKQuantityTypeIdentifierAppleSleepingWristTemperature", unit: .degreeCelsius())
    ]

    private let categoryTypeSpecs: [CategoryTypeSpec] = [
        .init(identifier: "HKCategoryTypeIdentifierSleepAnalysis"),
        .init(identifier: "HKCategoryTypeIdentifierAppleStandHour"),
        .init(identifier: "HKCategoryTypeIdentifierAudioExposureEvent"),
        .init(identifier: "HKCategoryTypeIdentifierHandwashingEvent"),
        .init(identifier: "HKCategoryTypeIdentifierHighHeartRateEvent"),
        .init(identifier: "HKCategoryTypeIdentifierLowHeartRateEvent"),
        .init(identifier: "HKCategoryTypeIdentifierIrregularHeartRhythmEvent"),
        .init(identifier: "HKCategoryTypeIdentifierLowCardioFitnessEvent"),
        .init(identifier: "HKCategoryTypeIdentifierShortnessOfBreath"),
        .init(identifier: "HKCategoryTypeIdentifierFatigue")
    ]

    func isHealthDataAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable() else {
            throw SyncError.healthDataUnavailable
        }

        let readTypes = Set(sampleTypes)
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func authorizationSummary() -> String {
        guard isHealthDataAvailable() else {
            return "不可用"
        }

        let sampleTypes = sampleTypes
        guard !sampleTypes.isEmpty else {
            return "未知"
        }

        let authorizedCount = sampleTypes.reduce(into: 0) { count, type in
            if store.authorizationStatus(for: type) == .sharingAuthorized {
                count += 1
            }
        }

        if authorizedCount == sampleTypes.count {
            return "已授权"
        }

        if authorizedCount > 0 {
            return "部分授权"
        }

        return "未决定"
    }

    var supportedTypeIdentifiers: [String] {
        resolvedQuantityTypes.map(\.spec.identifier) + resolvedCategoryTypes.map(\.spec.identifier)
    }

    func fetchAllAnchoredSamples(
        anchors: [String: HKQueryAnchor?],
        baselineStartAt: Date?,
        maxPerType: Int = 200,
        maxTotal: Int = 1_000
    ) async throws -> AnchoredFetchBatchResult {
        var results: [String: AnchoredSamplesResult] = [:]
        var remainingSampleBudget = maxTotal
        var reachedSyncLimit = false
        let predicate = Self.predicate(forBaselineStartAt: baselineStartAt)

        for entry in resolvedQuantityTypes {
            guard remainingSampleBudget > 0 else {
                reachedSyncLimit = true
                break
            }

            let key = entry.spec.identifier
            let result = try await fetchQuantitySamples(
                type: entry.type,
                typeIdentifier: key,
                unit: entry.spec.unit,
                predicate: predicate,
                anchor: anchors[key] ?? nil,
                limit: min(maxPerType, remainingSampleBudget)
            )
            results[key] = result
            remainingSampleBudget -= result.samples.count
            reachedSyncLimit = reachedSyncLimit || result.reachedQueryLimit
        }

        for entry in resolvedCategoryTypes {
            guard remainingSampleBudget > 0 else {
                reachedSyncLimit = true
                break
            }

            let key = entry.spec.identifier
            let result = try await fetchCategorySamples(
                type: entry.type,
                typeIdentifier: key,
                predicate: predicate,
                anchor: anchors[key] ?? nil,
                limit: min(maxPerType, remainingSampleBudget)
            )
            results[key] = result
            remainingSampleBudget -= result.samples.count
            reachedSyncLimit = reachedSyncLimit || result.reachedQueryLimit
        }

        return AnchoredFetchBatchResult(results: results, reachedSyncLimit: reachedSyncLimit)
    }

    func startObservers(
        baselineStartAt: Date?,
        onUpdate: @escaping @Sendable (String, @escaping () -> Void) -> Void
    ) async throws -> Int {
        let sampleEntries = resolvedSampleTypes
        let predicate = Self.predicate(forBaselineStartAt: baselineStartAt)
        guard !sampleEntries.isEmpty else {
            observerQueries.removeAll()
            return 0
        }

        if observerQueries.count == sampleEntries.count {
            return observerQueries.count
        }

        observerQueries.removeAll()

        for entry in sampleEntries {
            let query = HKObserverQuery(sampleType: entry.type, predicate: predicate) { _, completionHandler, error in
                if error != nil {
                    completionHandler()
                    return
                }
                // Pass completionHandler to the sync handler — it MUST call it
                // when sync is done so iOS keeps the app alive until then.
                onUpdate(entry.identifier, completionHandler)
            }
            observerQueries[entry.identifier] = query
            store.execute(query)
        }

        for entry in sampleEntries {
            try await enableBackgroundDelivery(for: entry.type)
        }

        return sampleEntries.count
    }

    func stopObservers() async {
        let sampleEntries = resolvedSampleTypes

        for query in observerQueries.values {
            store.stop(query)
        }
        observerQueries.removeAll()

        for entry in sampleEntries {
            await disableBackgroundDelivery(for: entry.type)
        }
    }
    private var sampleTypes: [HKSampleType] {
        let quantities = resolvedQuantityTypes.map(\.type)
        let categories = resolvedCategoryTypes.map(\.type)
        return quantities + categories
    }

    private var resolvedSampleTypes: [(identifier: String, type: HKSampleType)] {
        resolvedQuantityTypes.map { ($0.spec.identifier, $0.type as HKSampleType) }
        + resolvedCategoryTypes.map { ($0.spec.identifier, $0.type as HKSampleType) }
    }

    private var resolvedQuantityTypes: [(spec: QuantityTypeSpec, type: HKQuantityType)] {
        quantityTypeSpecs.compactMap { spec in
            let identifier = HKQuantityTypeIdentifier(rawValue: spec.identifier)
            guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
                return nil
            }
            return (spec, type)
        }
    }

    private var resolvedCategoryTypes: [(spec: CategoryTypeSpec, type: HKCategoryType)] {
        categoryTypeSpecs.compactMap { spec in
            let identifier = HKCategoryTypeIdentifier(rawValue: spec.identifier)
            guard let type = HKObjectType.categoryType(forIdentifier: identifier) else {
                return nil
            }
            return (spec, type)
        }
    }

    private func fetchQuantitySamples(
        type: HKQuantityType,
        typeIdentifier: String,
        unit: HKUnit,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?,
        limit: Int
    ) async throws -> AnchoredSamplesResult {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: predicate,
                anchor: anchor,
                limit: limit
            ) { _, samples, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let items = (samples as? [HKQuantitySample] ?? []).map { sample in
                    IngestItem(
                        source: "healthkit",
                        kind: "sample",
                        type: typeIdentifier,
                        uuid: sample.uuid.uuidString,
                        startAt: sample.startDate,
                        endAt: sample.endDate,
                        value: sample.quantity.doubleValue(for: unit),
                        unit: unit.unitString,
                        metadata: Self.metadata(for: sample, kind: "quantity")
                    )
                }

                continuation.resume(
                    returning: AnchoredSamplesResult(
                        samples: items,
                        newAnchor: newAnchor,
                        reachedQueryLimit: items.count >= limit
                    )
                )
            }

            store.execute(query)
        }
    }

    private func fetchCategorySamples(
        type: HKCategoryType,
        typeIdentifier: String,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?,
        limit: Int
    ) async throws -> AnchoredSamplesResult {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: predicate,
                anchor: anchor,
                limit: limit
            ) { _, samples, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let items = (samples as? [HKCategorySample] ?? []).map { sample in
                    IngestItem(
                        source: "healthkit",
                        kind: "sample",
                        type: typeIdentifier,
                        uuid: sample.uuid.uuidString,
                        startAt: sample.startDate,
                        endAt: sample.endDate,
                        value: Double(sample.value),
                        unit: nil,
                        metadata: Self.metadata(for: sample, kind: "category", typeIdentifier: typeIdentifier, categoryValue: sample.value)
                    )
                }

                continuation.resume(
                    returning: AnchoredSamplesResult(
                        samples: items,
                        newAnchor: newAnchor,
                        reachedQueryLimit: items.count >= limit
                    )
                )
            }

            store.execute(query)
        }
    }

    private static func metadata(
        for sample: HKSample,
        kind: String,
        typeIdentifier: String? = nil,
        categoryValue: Int? = nil
    ) -> [String: String] {
        var values: [String: String] = [:]

        if let sourceRevision = sample.sourceRevision.source.bundleIdentifier as String? {
            values["source_bundle_id"] = sourceRevision
        }

        values["source_name"] = sample.sourceRevision.source.name

        if let version = sample.sourceRevision.version {
            values["source_version"] = version
        }

        if let productType = sample.sourceRevision.productType {
            values["product_type"] = productType
        }

        values["sample_kind"] = kind

        if let device = sample.device {
            if let name = device.name {
                values["device_name"] = name
            }
            if let manufacturer = device.manufacturer {
                values["device_manufacturer"] = manufacturer
            }
            if let model = device.model {
                values["device_model"] = model
            }
            if let hardwareVersion = device.hardwareVersion {
                values["device_hardware_version"] = hardwareVersion
            }
            if let firmwareVersion = device.firmwareVersion {
                values["device_firmware_version"] = firmwareVersion
            }
            if let softwareVersion = device.softwareVersion {
                values["device_software_version"] = softwareVersion
            }
            if let localIdentifier = device.localIdentifier {
                values["device_local_identifier"] = localIdentifier
            }
            if let udiDeviceIdentifier = device.udiDeviceIdentifier {
                values["device_udi"] = udiDeviceIdentifier
            }
        }

        if let metadata = sample.metadata {
            for (key, rawValue) in metadata {
                let namespacedKey = "hk_metadata_\(key)"
                values[namespacedKey] = stringifyMetadataValue(rawValue)
            }
        }

        if let typeIdentifier, let categoryValue {
            values["category_value_raw"] = String(categoryValue)
            values["category_value_label"] = categoryValueLabel(for: typeIdentifier, value: categoryValue)
        }

        return values
    }

    private static func categoryValueLabel(for typeIdentifier: String, value: Int) -> String {
        switch typeIdentifier {
        case "HKCategoryTypeIdentifierSleepAnalysis":
            switch value {
            case 0:
                return "HKCategoryValueSleepAnalysisInBed"
            case 1:
                return "HKCategoryValueSleepAnalysisAsleepUnspecified"
            case 2:
                return "HKCategoryValueSleepAnalysisAwake"
            case 3:
                return "HKCategoryValueSleepAnalysisAsleepCore"
            case 4:
                return "HKCategoryValueSleepAnalysisAsleepDeep"
            case 5:
                return "HKCategoryValueSleepAnalysisAsleepREM"
            default:
                return "raw_\(value)"
            }
        case "HKCategoryTypeIdentifierAudioExposureEvent":
            switch value {
            case 1:
                return "HKCategoryValueAudioExposureEventLoudEnvironment"
            default:
                return "raw_\(value)"
            }
        case "HKCategoryTypeIdentifierAppleStandHour":
            switch value {
            case 0:
                return "HKCategoryValueAppleStandHourStood"
            case 1:
                return "HKCategoryValueAppleStandHourIdle"
            default:
                return "raw_\(value)"
            }
        case "HKCategoryTypeIdentifierHandwashingEvent":
            return "raw_\(value)"
        case "HKCategoryTypeIdentifierHighHeartRateEvent":
            return "raw_\(value)"
        case "HKCategoryTypeIdentifierLowHeartRateEvent":
            return "raw_\(value)"
        case "HKCategoryTypeIdentifierIrregularHeartRhythmEvent":
            return "raw_\(value)"
        case "HKCategoryTypeIdentifierLowCardioFitnessEvent":
            return "raw_\(value)"
        case "HKCategoryTypeIdentifierShortnessOfBreath":
            return "raw_\(value)"
        case "HKCategoryTypeIdentifierFatigue":
            return "raw_\(value)"
        default:
            return "raw_\(value)"
        }
    }

    private static func stringifyMetadataValue(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let quantity as HKQuantity:
            return quantity.description
        default:
            return String(describing: value)
        }
    }

    private static func predicate(forBaselineStartAt baselineStartAt: Date?) -> NSPredicate? {
        guard let baselineStartAt else {
            return nil
        }
        return HKQuery.predicateForSamples(
            withStart: baselineStartAt,
            end: nil,
            options: [.strictStartDate]
        )
    }

    private func enableBackgroundDelivery(for sampleType: HKSampleType) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SyncError.observerRegistrationFailed)
                }
            }
        }
    }

    private func disableBackgroundDelivery(for sampleType: HKSampleType) async {
        await withCheckedContinuation { continuation in
            store.disableBackgroundDelivery(for: sampleType) { _, _ in
                continuation.resume()
            }
        }
    }
}
