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

@Test func linkBreaksIntoWebsitePathWordsAndApp() {
    let parts = link("https://www.Linear.app/acme/issue/123", from: "com.tinyspeck.slackmacgap").ingredients
    #expect(parts == [.website("linear.app"), .pathWord("acme"), .pathWord("issue"), .pathWord("123"),
                      .app("com.tinyspeck.slackmacgap")])
}

@Test func pathWordsAreCappedAndDeduplicated() {
    let parts = link("https://a.com/x/x/b/c/d/e/f").ingredients
    #expect(parts == [.website("a.com"), .pathWord("x"), .pathWord("b"), .pathWord("c"), .pathWord("d")])
}

@Test func ruleBuiltFromPickedIngredientsMatchesTheLinkItCameFrom() {
    let original = link("https://www.linear.app/acme/issue/1", from: "com.tinyspeck.slackmacgap")
    let picked = original.ingredients.filter { if case .pathWord("issue") = $0 { false } else { true } }
    let rule = Rule(name: "x", when: picked.map(\.condition), open: work)
    let set = RuleSet(rules: [rule], fallback: personal)
    #expect(set.route(original).target == work)
    #expect(set.route(link("https://linear.app/other/issue/1", from: "com.tinyspeck.slackmacgap")).target == personal)
}

@Test func fixingTheRuleRetargetsExactlyTheOneThatDecided() {
    var set = RuleSet(rules: [
        Rule(name: "slack", when: [.app(["s"])], open: work, except: [
            Rule(name: "gh", when: [.host("github.com", .domain)], open: work),
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
