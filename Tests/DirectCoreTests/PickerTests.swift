import Foundation
import Testing
@testable import DirectCore

private func link(_ url: String, from app: String? = nil) -> Link {
    Link(url: URL(string: url)!, sourceApp: app)
}

private let work = Target(browser: "com.brave.Browser", profile: "Profile 14")
private let personal = Target(browser: "com.brave.Browser", profile: "Profile 13")

@Test func askFallbackLeavesTargetEmptyWhenNothingMatches() {
    let set = RuleSet(rules: [Rule(name: "gh", when: [.host("github.com", .domain)], open: work)], fallback: .ask)
    #expect(set.route(link("https://linear.app")).target == nil)
    #expect(set.route(link("https://github.com")).target == work)
}

@Test func fallbackReadsAndWritesBothForms() throws {
    let ask = try JSONDecoder().decode(RuleSet.self, from: Data(#"{ "rules": [], "fallback": "ask" }"#.utf8))
    #expect(ask.fallback == .ask)
    #expect(try JSONDecoder().decode(RuleSet.self, from: ask.encoded()) == ask)
    let open = RuleSet(rules: [], fallback: personal)
    #expect(try JSONDecoder().decode(RuleSet.self, from: open.encoded()) == open)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(RuleSet.self, from: Data(#"{ "rules": [], "fallback": "maybe" }"#.utf8))
    }
}

@Test func siteDropsWwwAndCase() {
    #expect(link("https://www.Linear.app/acme").site == "linear.app")
    #expect(link("https://admin.shopify.com/x").site == "admin.shopify.com")
}

@Test func fixingTheRuleRetargetsExactlyTheOneThatDecided() {
    var set = RuleSet(rules: [
        Rule(name: "slack", when: [.app(["s"])], open: work, except: [
            Exception(name: "gh", when: [.host("github.com", .domain)], open: work),
        ]),
    ], fallback: personal)
    let decision = set.route(link("https://github.com/x", from: "s"))
    let fixed = set.setTarget(personal, forRuleAt: decision.ruleIndices)
    #expect(fixed)
    #expect(set.rules[0].except[0].open == personal)
    #expect(set.rules[0].open == work)
    let noRule = set.setTarget(personal, forRuleAt: [])
    let missing = set.setTarget(personal, forRuleAt: [0, 5])
    #expect(!noRule && !missing)
}
