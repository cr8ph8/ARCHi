import Foundation

/// Availability policy only. Invalid proposals, stale context, user stops and
/// persistence failures never gain permission to leave the device here.
enum NativeAssistantFallback {
    static func isEligible(_ error: any Error) -> Bool {
        if error is LocalQwenRuntimeFailure { return true }
        if let local = error as? QwenFailure {
            switch local {
            case .unavailable, .modelUnavailable, .timedOut, .generationFailed: return true
            default: return false
            }
        }
        if let hampton = error as? HamptonAssistantFailure {
            return hampton == .timedOut
        }
        return false
    }
}
