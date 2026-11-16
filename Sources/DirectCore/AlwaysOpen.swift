import Foundation

/// What "Always use this for <host>" did to the rules.
public enum RuleSetChange: Equatable, Sendable {
    case addedRule(at: Int)
    case addedException(rule: Int, at: Int)
    case retargetedRule(Int)
    case retargetedException(rule: Int, at: Int)
    /// The rules already send this link there.
    case nothing
}

extension RuleSet {
    /// Makes links on `host` like `link` open in `target`, choosing the smallest change:
    /// - the rule that fired keeps its job, and gets an exception for the host
    /// - an exception that fired with exactly this host is repointed rather than duplicated
    /// - with no rule firing, a new rule for the host goes to the top
    /// Afterwards `route(link)` opens in `target`.
    @discardableResult
    public mutating func alwaysOpen(host: String, in target: Target, for link: Link) -> RuleSetChange {
        let decision = route(link)
        guard decision.target != target else { return .nothing }
        let condition = [Condition.host(host, .domain)]
        let exception = Exception(name: host, when: condition, open: target)

        switch decision.ruleIndices.count {
        case 1:
            let rule = decision.ruleIndices[0]
            // Same host already there but didn't fire, so it's off: turn it on instead of adding a twin.
            if let existing = rules[rule].except.firstIndex(where: { $0.when == condition }) {
                rules[rule].except[existing].open = target
                rules[rule].except[existing].enabled = true
                return .retargetedException(rule: rule, at: existing)
            }
            rules[rule].except.insert(exception, at: 0)
            return .addedException(rule: rule, at: 0)

        case 2:
            let (rule, fired) = (decision.ruleIndices[0], decision.ruleIndices[1])
            if rules[rule].except[fired].when == condition {
                rules[rule].except[fired].open = target
                return .retargetedException(rule: rule, at: fired)
            }
            if let existing = rules[rule].except.firstIndex(where: { $0.when == condition }) {
                var moved = rules[rule].except.remove(at: existing)
                moved.open = target
                moved.enabled = true
                let slot = min(fired, rules[rule].except.count)
                rules[rule].except.insert(moved, at: slot)
                return .retargetedException(rule: rule, at: slot)
            }
            rules[rule].except.insert(exception, at: fired)
            return .addedException(rule: rule, at: fired)

        default:
            if let existing = rules.firstIndex(where: { $0.when == condition && $0.except.isEmpty }) {
                rules[existing].open = target
                rules[existing].enabled = true
                return .retargetedRule(existing)
            }
            rules.insert(Rule(name: host, when: condition, open: target), at: 0)
            return .addedRule(at: 0)
        }
    }
}
