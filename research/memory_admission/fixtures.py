"""Deterministic, fictional records for the isolated memory-admission experiment.

There are no model calls and no imports from the admission implementation.  The
expected outcomes below are fixture specifications, not outputs of the gate.

``hidden_entities`` and ``truth`` belong only to the scoring oracle.  The runner
must remove both, together with all other scoring metadata, before constructing
the gate's state or candidate.  A source's ``subject_key`` is a *visible source
assertion*, deliberately separate from a hidden entity ID.

``eligible`` describes the visible evidence contract: two distinct active
provenance roots per record, consistent nonempty subject keys, and equal keys
across r1/r2.  It does not assert semantic truth.  In particular, the two
``assumption_challenge`` fixtures satisfy that contract while asserting a false
identity.  Their expected COMMIT exposes the limit of trusting source assertions.

Every proposed merge targets r1/r2.  An optional r3 is contextual only.  All
people, registries, ledger names, and source assertions are synthetic.
"""

from __future__ import annotations

from typing import Any


Case = dict[str, Any]


def _pair(
    case_id: str,
    category: str,
    names: tuple[str, str],
    keys: tuple[str, str],
    *,
    truth: str,
    eligible: bool,
    expected_decision: str,
    description: str,
    same_entity: bool | None,
    cohort: str = "contract",
    origins: tuple[str, ...] = ("cedar-register", "harbor-ledger"),
) -> Case:
    records: dict[str, Any] = {}
    sources: dict[str, Any] = {}
    for record_id, name, key in zip(("r1", "r2"), names, keys):
        source_ids = []
        for index, origin in enumerate(origins, start=1):
            source_id = f"{record_id}_s{index}"
            source_ids.append(source_id)
            sources[source_id] = {
                "record_id": record_id,
                "origin": origin,
                "subject_key": key,
                "active": True,
            }
        records[record_id] = {"name": name, "source_ids": source_ids}

    hidden_entities = {}
    if same_entity is not None:
        hidden_entities = {
            "r1": f"oracle-only:{case_id}:entity-a",
            "r2": f"oracle-only:{case_id}:entity-{'a' if same_entity else 'b'}",
        }
    return {
        "case_id": case_id,
        "category": category,
        "records": records,
        "sources": sources,
        "hidden_entities": hidden_entities,
        "truth": truth,
        "eligible": eligible,
        "cohort": cohort,
        "expected_decision": expected_decision,
        "description": description,
    }


def _add_source(
    case: Case, record_id: str, origin: str, key: str, *, active: bool = True
) -> None:
    source_id = f"{record_id}_s{len(case['records'][record_id]['source_ids']) + 1}"
    case["records"][record_id]["source_ids"].append(source_id)
    case["sources"][source_id] = {
        "record_id": record_id,
        "origin": origin,
        "subject_key": key,
        "active": active,
    }


def build_cases() -> list[Case]:
    """Return 24 fresh fixture dictionaries in a fixed, reproducible order."""
    cases: list[Case] = []

    positive_specs = (
        ("exact_name", ("Mira Vale", "Mira Vale"), "urn:cedar:person:104",
         "Matching display names and corroborated matching subject assertions."),
        ("initial_alias", ("Tess Rowan", "T. Rowan"), "urn:cedar:person:218",
         "An initial alias is supported by matching identifiers from two roots."),
        ("changed_display_name", ("Arden Pike", "Arden Reed"), "urn:cedar:person:327",
         "Different display surnames share the same corroborated identifier."),
        ("case_and_spacing", ("Cato Noll", "  cato noll  "), "urn:cedar:person:435",
         "Display-name case and spacing do not override matching identifiers."),
        ("diacritic_variant", ("Elin Soren", "Elín Søren"), "urn:cedar:person:546",
         "A diacritic variant is linked by corroborated identifiers, not spelling."),
        ("distinct_handle", ("Lina Voss", "Blue Moth"), "urn:cedar:person:652",
         "A distinct display handle is supported by matching source assertions."),
    )
    for case_id, names, key, description in positive_specs:
        cases.append(_pair(
            case_id, "eligible_identity", names, (key, key), truth="same",
            eligible=True, expected_decision="COMMIT", description=description,
            same_entity=True,
        ))

    case = _pair(
        "extra_correlated_copy", "eligible_identity", ("Emery Quill", "E. Quill"),
        ("urn:cedar:person:761",) * 2, truth="same", eligible=True,
        expected_decision="COMMIT", same_entity=True,
        description="An extra copied assertion adds no independence, but two valid roots remain.",
    )
    _add_source(case, "r1", "cedar-register", "urn:cedar:person:761")
    cases.append(case)

    case = _pair(
        "inactive_obsolete_conflict", "eligible_identity", ("Bryn Fen", "B. Fen"),
        ("urn:cedar:person:873",) * 2, truth="same", eligible=True,
        expected_decision="COMMIT", same_entity=True,
        description="An inactive obsolete assertion does not contradict two current agreeing roots.",
    )
    _add_source(case, "r2", "retired-copper-index", "urn:retired:person:999", active=False)
    cases.append(case)

    negative_specs = (
        ("shared_display_name", ("Mira Vale", "Mira Vale"),
         ("urn:cedar:person:901", "urn:cedar:person:902"),
         "Identical display names refer to distinct entities with different corroborated keys."),
        ("initial_collision", ("Emery Quill", "E. Quill"),
         ("urn:cedar:person:903", "urn:cedar:person:904"),
         "A plausible initial alias is actually another entity."),
        ("near_identifier_collision", ("Tess Rowan", "Tess Rowan"),
         ("urn:cedar:person:71", "urn:cedar:person:071"),
         "Similar-looking subject identifiers are distinct literal identifiers."),
    )
    for case_id, names, keys, description in negative_specs:
        cases.append(_pair(
            case_id, "conflicting_identity", names, keys, truth="different",
            eligible=False, expected_decision="REJECT", description=description,
            same_entity=False,
        ))

    case = _pair(
        "contradiction_within_record", "conflicting_identity", ("Cato Noll", "C. Noll"),
        ("urn:cedar:person:905",) * 2, truth="different", eligible=False,
        expected_decision="REJECT", same_entity=False,
        description="One record's two active roots disagree about identity.",
    )
    case["sources"]["r1_s2"]["subject_key"] = "urn:cedar:person:906"
    cases.append(case)

    case = _pair(
        "third_root_contradicts", "conflicting_identity", ("Arden Pike", "A. Pike"),
        ("urn:cedar:person:907",) * 2, truth="different", eligible=False,
        expected_decision="REJECT", same_entity=False,
        description="A third active contradictory root must not be outvoted by two matching roots.",
    )
    _add_source(case, "r2", "birch-roster", "urn:cedar:person:908")
    cases.append(case)

    case = _pair(
        "lexical_similarity_bridge", "conflicting_identity",
        ("Mira Vale lunar", "Mira Vess glass"),
        ("urn:cedar:person:909", "urn:cedar:person:910"), truth="different",
        eligible=False, expected_decision="REJECT", same_entity=False,
        description="Context record r3 shares visible name tokens with both targets; it does not establish r1/r2 identity.",
    )
    case["records"]["r3"] = {"name": "Mira Vale Vess lunar glass", "source_ids": []}
    _add_source(case, "r3", "cedar-register", "urn:cedar:person:911")
    _add_source(case, "r3", "harbor-ledger", "urn:cedar:person:911")
    case["hidden_entities"]["r3"] = "oracle-only:lexical_similarity_bridge:entity-c"
    cases.append(case)

    case = _pair(
        "single_root", "insufficient_evidence", ("Lina Voss", "L. Voss"),
        ("urn:cedar:person:801",) * 2, truth="same", eligible=False,
        expected_decision="DAMP", same_entity=True, origins=("cedar-register",),
        description="The identity is true, but each record has only one provenance root.",
    )
    cases.append(case)

    case = _pair(
        "many_copies_one_root", "insufficient_evidence", ("Elin Soren", "E. Soren"),
        ("urn:cedar:person:802",) * 2, truth="same", eligible=False,
        expected_decision="DAMP", same_entity=True,
        origins=("cedar-register", "cedar-register", "cedar-register", "cedar-register"),
        description="Eight assertions copied from one root do not supply independent corroboration.",
    )
    cases.append(case)

    case = _pair(
        "asymmetric_root_coverage", "insufficient_evidence", ("Bryn Fen", "B. Fen"),
        ("urn:cedar:person:803",) * 2, truth="same", eligible=False,
        expected_decision="DAMP", same_entity=True,
        description="Two roots for r1 cannot compensate for only one active root for r2.",
    )
    case["records"]["r2"]["source_ids"].remove("r2_s2")
    del case["sources"]["r2_s2"]
    cases.append(case)

    case = _pair(
        "all_sources_inactive", "insufficient_evidence", ("Emery Quill", "E. Quill"),
        ("urn:cedar:person:804",) * 2, truth="same", eligible=False,
        expected_decision="DAMP", same_entity=True,
        description="Historical assertions provide no current active corroboration.",
    )
    for source in case["sources"].values():
        source["active"] = False
    cases.append(case)

    case = _pair(
        "missing_source_reference", "insufficient_evidence", ("Tess Rowan", "T. Rowan"),
        ("urn:cedar:person:805",) * 2, truth="same", eligible=False,
        expected_decision="DAMP", same_entity=True,
        description="A listed source is unavailable; r1 has only one inspectable root.",
    )
    del case["sources"]["r1_s2"]
    cases.append(case)

    case = _pair(
        "no_evidence_unknown_identity", "unknown_identity", ("M. Vale", "M. Vale"),
        ("", ""), truth="unknown", eligible=False, expected_decision="DAMP",
        same_entity=None, origins=(),
        description="Names alone do not establish identity, and this fixture supplies no hidden identity truth.",
    )
    cases.append(case)

    case = _pair(
        "empty_subject_assertions", "insufficient_evidence", ("Cato Noll", "C. Noll"),
        ("", ""), truth="same", eligible=False, expected_decision="DAMP",
        same_entity=True,
        description="Independent documents with empty subject keys do not establish an identity claim.",
    )
    cases.append(case)

    case = _pair(
        "inactive_second_root", "insufficient_evidence", ("Arden Pike", "A. Pike"),
        ("urn:cedar:person:806",) * 2, truth="same", eligible=False,
        expected_decision="DAMP", same_entity=True,
        description="Each record has one current root and one inactive root, which is insufficient.",
    )
    case["sources"]["r1_s2"]["active"] = False
    case["sources"]["r2_s2"]["active"] = False
    cases.append(case)

    cases.append(_pair(
        "false_consensus_same_name", "false_consistent_sources", ("Mira Vale", "Mira Vale"),
        ("urn:cedar:person:991",) * 2, truth="different", eligible=True,
        expected_decision="COMMIT", same_entity=False, cohort="assumption_challenge",
        description="All designated trusted roots make the same false identity assertion about two different entities.",
    ))

    case = _pair(
        "false_consensus_distinct_names", "false_consistent_sources", ("Lina Voss", "Blue Moth"),
        ("urn:cedar:person:992",) * 2, truth="different", eligible=True,
        expected_decision="COMMIT", same_entity=False, cohort="assumption_challenge",
        description="Four designated independent roots falsely agree on identity despite different entities and display names.",
    )
    case["sources"]["r2_s1"]["origin"] = "birch-roster"
    case["sources"]["r2_s2"]["origin"] = "copper-index"
    cases.append(case)

    return cases
