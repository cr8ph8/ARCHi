import Foundation

extension ARCCapabilitiesEvaluator {
    // Same frozen synthetic inputs as arc/fixtures/portable/smoke-evaluation-v1.json.
    // Deliberately includes an incorrect prediction; no model is invoked.
    static let syntheticBundle = Data(#"""
{"schema":"archi-arc-evaluation-bundle/v1","manifest":{"schemaVersion":1,"manifestId":"archi-synthetic-smoke-v1","mode":"fixture","integration":"none","scorerVersion":"archi-arc-exact-v1","source":{"label":"ARCHi synthetic ARC-format smoke fixtures","status":"synthetic-fixture","snapshot":"2026-08-28","contentHash":"sha256:f45cf7721b3678f2fec2d35b529c26ec4eed21264e49582e8b2848776bc1f2d0"},"split":"smoke","tasks":[{"taskId":"synthetic-increment-001","taskHash":"sha256:e31aa2467a609f8c3da50e8539601fa3bd8d8763d72840488406d1f6bed395e6","testExamples":2}]},"solver":{"id":"archi-test-solver","version":"0.0.1","codeHash":"sha256:6abe967e95ffbb0f4fd7aa0034d770c7f0852496839461ccaf4cb83d8bf076ea","configurationHash":"sha256:ccc792072dd056a9ab3513875a46d1146fed3fbc82252458e78d019da0189de7"},"evaluations":[{"task":{"taskId":"synthetic-increment-001","train":[{"input":[[0,1],[1,0]],"output":[[0,2],[2,0]]},{"input":[[3]],"output":[[4]]}],"test":[{"input":[[1,0,1]],"output":[[2,0,2]]},{"input":[[5,5],[0,5]],"output":[[6,6],[0,6]]}]},"predictions":[[[2,0,2]],[[6,6],[0,5]]]}]}
"""#.utf8)
}
