import Foundation
import SurfaceDeviceContracts

public enum PlanAuthorization: Equatable, Sendable {
    case granted(directions: Set<EffectDirection>)
    case denied(reason: String)
}

/// Produced by the trusted adapter's actual final device gates for this plan.
/// No optional policy switch or default passing value exists in this API.
public enum NativeSafetyResult: Equatable, Sendable {
    case passed
    case rejected(reason: String)
}

/// The full plan, not its reference alone, binds the explicit native results.
/// NativeSnapshot must be current native gate facts, with pure value equality.
public struct FeedbackProof<Plan: Equatable & Sendable, NativeSnapshot: Equatable & Sendable>: Equatable, Sendable {
    public let plan: Plan
    public let nativeSnapshot: NativeSnapshot
    public let authorization: PlanAuthorization
    public let safety: NativeSafetyResult

    public init(plan: Plan, nativeSnapshot: NativeSnapshot, authorization: PlanAuthorization, safety: NativeSafetyResult) {
        self.plan = plan
        self.nativeSnapshot = nativeSnapshot
        self.authorization = authorization
        self.safety = safety
    }
}

public enum FeedbackRejection: Equatable, Sendable {
    case planMismatch
    case staleScope
    case staleNativeProof
    case authorizationDenied(reason: String)
    case wrongDirections(missing: Set<EffectDirection>, surplus: Set<EffectDirection>)
    case nativeRejected(reason: String)
}

/// A stage-only authorization result, never a final send permit. Explicit stage
/// requirements preserve native early returns before a mutating safety filter.
public enum FeedbackAuthorizationCheck: Equatable, Sendable {
    case sufficient
    case rejected(FeedbackRejection)

    public static func evaluate(requirements: Set<EffectDirection>, authorization: PlanAuthorization) -> Self {
        switch authorization {
        case .denied(let reason): return .rejected(.authorizationDenied(reason: reason))
        case .granted(let directions):
            let missing = requirements.subtracting(directions)
            let surplus = directions.subtracting(requirements)
            guard missing.isEmpty, surplus.isEmpty else { return .rejected(.wrongDirections(missing: missing, surplus: surplus)) }
            return .sufficient
        }
    }
}

/// Pure preflight only. A permitted value does not dispatch, retry, record a
/// receipt or replace the actual native transport pin and final device policy.
public enum FeedbackPreflight: Equatable, Sendable {
    case permitted
    case rejected(FeedbackRejection)

    public static func evaluate<Payload, Origin, Scope, Reference, CapturedEvidence, NativeSnapshot>(
        plan: FeedbackPlan<Payload, Origin, Scope, Reference, CapturedEvidence>,
        proof: FeedbackProof<FeedbackPlan<Payload, Origin, Scope, Reference, CapturedEvidence>, NativeSnapshot>,
        currentScope: Scope, currentNativeSnapshot: NativeSnapshot
    ) -> FeedbackPreflight {
        guard proof.plan == plan else { return .rejected(.planMismatch) }
        guard plan.scope == currentScope else { return .rejected(.staleScope) }
        guard proof.nativeSnapshot == currentNativeSnapshot else { return .rejected(.staleNativeProof) }
        switch FeedbackAuthorizationCheck.evaluate(requirements: plan.requiredDirections, authorization: proof.authorization) {
        case .rejected(let rejection): return .rejected(rejection)
        case .sufficient: break
        }
        switch proof.safety {
        case .passed: return .permitted
        case .rejected(let reason): return .rejected(.nativeRejected(reason: reason))
        }
    }
}
