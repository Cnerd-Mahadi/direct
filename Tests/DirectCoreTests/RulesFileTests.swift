import Foundation
import Testing
@testable import DirectCore

@Test func handWrittenRulesFileDecodesWithDefaults() throws {
    let json = """
    {
      "fallback": { "browser": "com.brave.Browser", "profile": "Profile 13" },
      "rules": [
        {
          "name": "Teams to Work",
          "when": [ { "app": "com.microsoft.teams2" } ],
          "open": { "browser": "com.brave.Browser", "profile": "Profile 14" },
          "except": [
            { "name": "Docs", "when": [ { "url": "Docs", "caseSensitive": true } ],
              "open": { "browser": "com.apple.Safari" } }
          ]
        },
        { "name": "GitHub", "when": [ { "host": "github.com" } ], "open": { "browser": "com.google.Chrome" } }
      ]
    }
    """
    let set = try JSONDecoder().decode(RuleSet.self, from: Data(json.utf8))
    #expect(set.rules[0].enabled)
    #expect(set.rules[0].when == [.app(["com.microsoft.teams2"])])
    #expect(set.rules[0].except[0].when == [.url("Docs", .contains, caseSensitive: true)])
    #expect(set.rules[1].when == [.host("github.com", .domain)])
    #expect(set.rules[1].except.isEmpty)
}

@Test func rulesFileRoundTrips() throws {
    let set = RuleSet(rules: [
        Rule(name: "a", enabled: false, when: [
            .host("x.com", .exactly), .path("/p", .startsWith, caseSensitive: true),
            .url("q", .endsWith, caseSensitive: false), .app(["one", "two"]),
        ], open: Target(browser: "b", profile: "Profile 1"),
             except: [Exception(name: "b", when: [], open: Target(browser: "c"))]),
    ], fallback: Target(browser: "com.apple.Safari"))
    #expect(try JSONDecoder().decode(RuleSet.self, from: set.encoded()) == set)
}

@Test func conditionWithTwoSubjectsIsRejected() {
    let json = #"{ "host": "a.com", "url": "b" }"#
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(Condition.self, from: Data(json.utf8)) }
}

@Test func profilesAreReadFromLocalState() throws {
    let json = #"{ "profile": { "info_cache": { "Profile 14": { "name": "Work" }, "Profile 2": { "name": "Me" } }, "last_used": "Profile 2" } }"#
    let profiles = try Chromium.profiles(localState: Data(json.utf8))
    #expect(profiles == [.init(directory: "Profile 2", name: "Me"), .init(directory: "Profile 14", name: "Work")])
}

@Test func singletonMessageMatchesChromiumWireFormat() {
    let data = Chromium.singletonMessage(executable: "/B", profile: "Profile 14", url: URL(string: "https://a.com/x?y=1")!)
    #expect(String(decoding: data, as: UTF8.self) == "START\0/\0/B\0--profile-directory=Profile 14\0https://a.com/x?y=1")
}

@Test func shippedExampleRulesFileLoads() throws {
    let file = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Support/rules.example.json")
    let set = try RuleSet.load(from: file)
    #expect(set.route(Link(url: URL(string: "https://x.com")!, sourceApp: "com.microsoft.teams2")).rulePath == ["Teams goes to Work"])
}

@Test func exceptionInsideExceptionIsRejectedWithAClearMessage() {
    let json = """
    { "fallback": "ask", "rules": [ { "name": "a", "when": [], "open": { "browser": "b" },
      "except": [ { "name": "e", "when": [], "open": { "browser": "c" },
                    "except": [ { "name": "deeper", "when": [], "open": { "browser": "d" } } ] } ] } ] }
    """
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(RuleSet.self, from: Data(json.utf8)) }
}
