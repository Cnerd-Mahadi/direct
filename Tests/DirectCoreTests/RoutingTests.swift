import Foundation
import Testing
@testable import DirectCore

private let slack = "com.tinyspeck.slackmacgap"
private let mail = "com.apple.mail"
private let work = Target(browser: "com.brave.Browser", profile: "Profile 14")
private let personal = Target(browser: "com.brave.Browser", profile: "Profile 13")
private let safari = Target(browser: "com.apple.Safari")

private func link(_ url: String, from app: String? = nil) -> Link {
    Link(url: URL(string: url)!, sourceApp: app)
}

private let slackRules = RuleSet(
    rules: [
        Rule(name: "Slack goes to Work", when: [.app([slack])], open: work, except: [
            Rule(name: "GitHub stays personal", when: [.host("github.com", .domain)], open: personal),
        ]),
    ],
    fallback: safari
)

@Test func appRuleSendsSlackLinksToWork() {
    let d = slackRules.route(link("https://linear.app/acme/issue/1", from: slack))
    #expect(d.target == work)
    #expect(d.rulePath == ["Slack goes to Work"])
}

@Test func exceptionOverridesParentWhenBothMatch() {
    let d = slackRules.route(link("https://gist.github.com/abc", from: slack))
    #expect(d.target == personal)
    #expect(d.rulePath == ["Slack goes to Work", "GitHub stays personal"])
}

@Test func exceptionInheritsParentConditions() {
    let d = slackRules.route(link("https://github.com/acme/repo", from: mail))
    #expect(d.target == safari)
    #expect(d.rulePath.isEmpty)
}

@Test func unknownSourceAppNeverMatchesAppCondition() {
    #expect(slackRules.route(link("https://linear.app")).target == safari)
}

@Test func domainMatchCoversSubdomainsButNotLookalikes() {
    let c = Condition.host("github.com", .domain)
    #expect(c.matches(link("https://github.com")))
    #expect(c.matches(link("https://api.GitHub.com/x")))
    #expect(!c.matches(link("https://notgithub.com")))
    #expect(!c.matches(link("https://github.com.evil.io")))
}

@Test func exactHostDoesNotCoverSubdomains() {
    let c = Condition.host("github.com", .exactly)
    #expect(c.matches(link("https://github.com/a")))
    #expect(!c.matches(link("https://gist.github.com/a")))
}

@Test func textMatchIgnoresCaseUnlessAsked() {
    #expect(Condition.url("ACME", .contains, caseSensitive: false).matches(link("https://x.com/acme/1")))
    #expect(!Condition.url("ACME", .contains, caseSensitive: true).matches(link("https://x.com/acme/1")))
    #expect(Condition.path("/acme", .startsWith, caseSensitive: false).matches(link("https://x.com/acme/1")))
    #expect(!Condition.path("/acme", .startsWith, caseSensitive: false).matches(link("https://x.com/team/acme")))
}

@Test func firstMatchingTopLevelRuleWins() {
    let rules = RuleSet(rules: [
        Rule(name: "first", when: [.host("figma.com", .domain)], open: work),
        Rule(name: "second", when: [.host("figma.com", .domain)], open: personal),
    ], fallback: safari)
    #expect(rules.route(link("https://www.figma.com/file/1")).rulePath == ["first"])
}

@Test func disabledRulesAndExceptionsAreSkipped() {
    var rules = slackRules
    rules.rules[0].except[0].enabled = false
    #expect(rules.route(link("https://github.com", from: slack)).target == work)
    rules.rules[0].enabled = false
    #expect(rules.route(link("https://github.com", from: slack)).target == safari)
}

@Test func allConditionsMustMatch() {
    let rules = RuleSet(rules: [
        Rule(name: "Slack + Linear", when: [.app([slack]), .host("linear.app", .domain)], open: work),
    ], fallback: safari)
    #expect(rules.route(link("https://linear.app/x", from: slack)).target == work)
    #expect(rules.route(link("https://linear.app/x", from: mail)).target == safari)
    #expect(rules.route(link("https://notion.so/x", from: slack)).target == safari)
}
