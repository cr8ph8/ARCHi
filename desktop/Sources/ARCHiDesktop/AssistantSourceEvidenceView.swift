import SwiftUI

struct AssistantSourceEvidenceView: View {
    let receipt: AssistantLaneReceipt
    var body: some View {
        if let evidence = AssistantSourceEvidence(receipt: receipt) {
            DisclosureGroup("Sources for this reply · \(evidence.rows.count)") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(evidence.status).accessibilityIdentifier("answer.sources.status")
                    Text(evidence.coverage).foregroundStyle(.secondary)
                    ForEach(evidence.rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.excerpt.title).fontWeight(.medium)
                            Text((row.excerpt.kind == .interpretation ? "Authored interpretation" : "Source passage") + " · " + row.delivery.rawValue)
                                .foregroundStyle(.secondary)
                            if row.excerpt.kind == .passage {
                                if let provenance = row.excerpt.provenance {
                                    Text(provenance.origin.title + " · " + provenance.acquisition.title + " · declared, not verified")
                                    if !provenance.parents.isEmpty {
                                        Text("Derived from \(provenance.parents.count) exact kept source version(s).")
                                    }
                                } else { Text("Origin unknown · no declaration captured") }
                            }
                            DisclosureGroup("Read captured text") {
                                Text(row.excerpt.text).textSelection(.enabled)
                                Text(row.excerpt.detail).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }
                    if evidence.unmatchedCitationCount > 0 {
                        Text("\(evidence.unmatchedCitationCount) other cited reference(s) are listed in Request details; they are not linked to the excerpts above.")
                    }
                    Text("Captured for this request. A citation identifies text; it does not establish that the text supports the answer or that the answer was useful. Nothing is saved by opening this view.")
                        .foregroundStyle(.secondary)
                }.padding(.top, 5)
            }.font(.caption).accessibilityIdentifier("answer.sources")
        }
    }
}
