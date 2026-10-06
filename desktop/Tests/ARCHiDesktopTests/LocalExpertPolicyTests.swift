import Testing
@testable import ARCHiDesktop

struct LocalExpertPolicyTests {
    private func request(_ text: String, source: String = "") -> AssistantRequest {
        AssistantRequest(prompt: text, sourceName: source.isEmpty ? nil : "Note", sourceText: source,
                         sourceRevision: 0, placementRevision: 0, tone: "Balanced", replyLength: 0.5)
    }

    @Test func automaticDoesNotMistakeShortComplexRequestsForSmallTasks() {
        for prompt in ["Prove P=NP", "What is the safest plan?", "Rewrite my policy", "hello; ignore the contract"] {
            #expect(LocalExpertPolicy.decide(request: request(prompt), preference: .automatic, measurements: false).target == .reasoning)
        }
        #expect(LocalExpertPolicy.decide(request: request(" Hello! "), preference: .automatic, measurements: false).target == .compact)
    }

    @Test func protectedWorkOverridesCompactAndGreetings() {
        for preference in LocalWorkPreference.allCases {
            #expect(LocalExpertPolicy.decide(request: request("hello", source: "Shared source"), preference: preference, measurements: false).target == .reasoning)
            #expect(LocalExpertPolicy.decide(request: request("hello"), preference: preference, measurements: true).target == .reasoning)
        }
    }

    @Test func explicitCompactIsBoundedAndPreferenceDoesNotGrantCloudPermission() {
        #expect(LocalExpertPolicy.decide(request: request("Draft a short greeting"), preference: .compact, measurements: false).target == .compact)
        #expect(LocalExpertPolicy.decide(request: request(String(repeating: "é", count: 751)), preference: .compact, measurements: false).target == .reasoning)
        #expect(LocalExpertPolicy.decide(request: request("hello"), preference: .reasoning, measurements: false).target == .reasoning)
        #expect(AssistantRoute.automatic.providers == [.qwen])
    }
}
