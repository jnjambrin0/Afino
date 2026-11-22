import Foundation
import PIProviders

/// What one streamed request produced.
struct CollectedStream: Sendable, Hashable {
    /// The accumulated text deltas, before post-processing.
    var rawText: String
    var measurement: TurnMeasurement
}

/// Drains an engine stream, timing it the way a person experiences it.
enum StreamCollector {
    /// Sends `request` and waits for the stream to end. Never throws: a failure is recorded in
    /// the measurement as the `EngineError` case.
    static func collect(
        _ request: EngineRequest,
        provider: any PromptEngineProvider,
        key: APIKey,
        clock: ContinuousClock = ContinuousClock()
    ) async -> CollectedStream {
        let start = clock.now
        /// Seconds since the request was handed over, to a tenth of a millisecond.
        func elapsed() -> Double { (seconds(start.duration(to: clock.now)) * 10_000).rounded() / 10_000 }

        var text = ""
        var measurement = TurnMeasurement()
        do {
            for try await event in provider.stream(request, key: key) {
                if measurement.timeToFirstEvent == nil { measurement.timeToFirstEvent = elapsed() }
                switch event {
                case .retrying:
                    measurement.retries += 1
                case .started(let servedModel, let requestID):
                    measurement.servedModel = servedModel
                    measurement.requestID = requestID ?? measurement.requestID
                case .thinking:
                    break
                case .textDelta(let delta):
                    if measurement.timeToFirstText == nil { measurement.timeToFirstText = elapsed() }
                    text += delta
                case .finished(let reason, let usage):
                    measurement.finishReason = TurnMeasurement.finishName(reason)
                    measurement.usage = usage.map(UsageRecord.init)
                }
            }
        } catch {
            let failure = EngineFailure(normalizing: error, provider: provider.id)
            measurement.error = ErrorRecord(failure)
            if failure.requestID == nil, let requestID = measurement.requestID {
                measurement.error?.requestID = requestID
            }
        }
        measurement.totalTime = elapsed()
        return CollectedStream(rawText: text, measurement: measurement)
    }

    /// `duration` in seconds.
    static func seconds(_ duration: Duration) -> Double {
        let (whole, attoseconds) = duration.components
        return Double(whole) + Double(attoseconds) * 1e-18
    }
}
