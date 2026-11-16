import Foundation
import Testing
@testable import DirectCore

private func link(_ url: String, from app: String? = nil) -> Link {
    Link(url: URL(string: url)!, sourceApp: app)
}

@Test func emptyConditionsNeverMatch() {
    #expect(!Condition.url("", .contains, caseSensitive: false).matches(link("https://a.com")))
    #expect(!Condition.url("   ", .contains, caseSensitive: false).matches(link("https://a.com")))
    #expect(!Condition.path("", .startsWith, caseSensitive: false).matches(link("https://a.com/x")))
    #expect(!Condition.host("", .contains).matches(link("https://a.com")))
    #expect(!Condition.app([]).matches(link("https://a.com", from: "x")))
}

@Test func newRuleFromTheWindowCatchesNothingUntilFilledIn() {
    var draft = RuleDraft(name: "New rule", target: Target(browser: "b"))
    let set = { RuleSet(rules: [draft.rule], fallback: Target(browser: "fallback")) }
    #expect(set().route(link("https://github.com")).target?.browser == "fallback")
    draft.conditions[0].text = "github.com"
    #expect(set().route(link("https://github.com")).target?.browser == "b")
}

@Test func pastedLinkInWebsiteFieldBecomesHost() {
    var draft = ConditionDraft(kind: .website)
    draft.text = "  https://GitHub.com/acme/repo?x=1 "
    #expect(draft.condition == .host("github.com", .domain))
    draft.text = "github.com/acme"
    #expect(draft.condition == .host("github.com", .domain))
}

@Test func switchingKindKeepsTextAndFixesInvalidMatch() {
    var draft = ConditionDraft(kind: .website)
    draft.text = "acme"
    draft.match = .isOrUnder
    draft.kind = .link
    #expect(draft.text == "acme")
    #expect(draft.condition == .url("acme", .contains, caseSensitive: false))
    draft.match = .startsWith
    draft.kind = .path
    #expect(draft.match == .startsWith)
}

@Test func draftsRoundTripEveryConditionShape() {
    let rule = Rule(name: "r", enabled: false, when: [
        .host("a.com", .exactly), .host("b.com", .domain), .host("c", .contains),
        .path("/p", .startsWith, caseSensitive: true), .url("q", .endsWith, caseSensitive: false),
        .url("z", .exactly, caseSensitive: true), .app(["one", "two"]),
    ], open: Target(browser: "x", profile: "Profile 1"), except: [
        Exception(name: "e", when: [.host("d.com", .domain)], open: Target(browser: "y")),
    ])
    #expect(RuleDraft(rule).rule == rule)
}

@Test func decisionPointsAtTheExactRuleThatMatched() {
    let set = RuleSet(rules: [
        Rule(name: "same", when: [.host("a.com", .domain)], open: Target(browser: "1")),
        Rule(name: "same", when: [.host("b.com", .domain)], open: Target(browser: "2"), except: [
            Exception(name: "x", when: [.path("/x", .startsWith, caseSensitive: false)], open: Target(browser: "3")),
        ]),
    ], fallback: Target(browser: "f"))
    #expect(set.route(link("https://b.com/y")).ruleIndices == [1])
    #expect(set.route(link("https://b.com/x")).ruleIndices == [1, 0])
    #expect(set.route(link("https://c.com")).ruleIndices == [])
}
