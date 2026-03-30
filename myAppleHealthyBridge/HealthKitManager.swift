import Foundation
import HealthKit

struct AnchoredSamplesResult {
    let samples: [IngestItem]
    let newAnchor: HKQueryAnchor?
}

final class HealthKitManager {
    private let store = HKHealthStore()

    private let quantityTypes: [(identifier: HKQuantityTypeIdentifier, unit: HKUnit)] = [
        (.heartRate, HKUnit.count().unitDivided(by: .minute())),
        (.oxygenSaturation, HKUnit.percent()),
        (.respiratoryRate, HKUnit.count().unitDivided(by: .minute())),
        (.stepCount, HKUnit.count())
    ]

    private let categoryTypes: [HKCategoryTypeIdentifier] = [
        .sleepAnalysis
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
            return "Unavailable"
        }

        let sampleTypes = sampleTypes
        guard !sampleTypes.isEmpty else {
            return "Unknown"
        }

        let authorizedCount = sampleTypes.reduce(into: 0) { count, type in
            if store.authorizationStatus(for: type) == .sharingAuthorized {
                count += 1
            }
        }

        if authorizedCount == sampleTypes.count {
            return "Authorized"
        }

        if authorizedCount > 0 {
            return "Partially Authorized"
        }

        return "Not Determined"
    }

    var supportedTypeIdentifiers: [String] {
        quantityTypes.map(\.identifier.rawValue) + categoryTypes.map(\.rawValue)
    }

    func fetchAllAnchoredSamples(anchors: [String: HKQueryAnchor?]) async throws -> [String: AnchoredSamplesResult] {
        var results: [String: AnchoredSamplesResult] = [:]

        for (identifier, unit) in quantityTypes {
            let key = identifier.rawValue
            let type = try requireQuantityType(identifier)
            results[key] = try await fetchQuantitySamples(
                type: type,
                typeIdentifier: key,
                unit: unit,
                anchor: anchors[key] ?? nil
            )
        }

        for identifier in categoryTypes {
            let key = identifier.rawValue
            let type = try requireCategoryType(identifier)
            results[key] = try await fetchCategorySamples(
                type: type,
                typeIdentifier: key,
                anchor: anchors[key] ?? nil
            )
        }

        return results
    }
    private var sampleTypes: [HKSampleType] {
        let quantities = quantityTypes.compactMap { HKObjectType.quantityType(forIdentifier: $0.identifier) }
        let categories = categoryTypes.compactMap { HKObjectType.categoryType(forIdentifier: $0) }
        return quantities + categories
    }

    private func fetchQuantitySamples(
        type: HKQuantityType,
        typeIdentifier: String,
        unit: HKUnit,
        anchor: HKQueryAnchor?
    ) async throws -> AnchoredSamplesResult {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
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
                        metadata: Self.metadata(for: sample)
                    )
                }

                continuation.resume(returning: AnchoredSamplesResult(samples: items, newAnchor: newAnchor))
            }

            store.execute(query)
        }
    }

    private func fetchCategorySamples(
        type: HKCategoryType,
        typeIdentifier: String,
        anchor: HKQueryAnchor?
    ) async throws -> AnchoredSamplesResult {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
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
                        metadata: Self.metadata(for: sample)
                    )
                }

                continuation.resume(returning: AnchoredSamplesResult(samples: items, newAnchor: newAnchor))
            }

            store.execute(query)
        }
    }

    private static func metadata(for sample: HKSample) -> [String: String] {
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

        return values
    }

    private func requireQuantityType(_ identifier: HKQuantityTypeIdentifier) throws -> HKQuantityType {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw SyncError.unsupportedSampleType(identifier.rawValue)
        }
        return type
    }

    private func requireCategoryType(_ identifier: HKCategoryTypeIdentifier) throws -> HKCategoryType {
        guard let type = HKObjectType.categoryType(forIdentifier: identifier) else {
            throw SyncError.unsupportedSampleType(identifier.rawValue)
        }
        return type
    }
}
