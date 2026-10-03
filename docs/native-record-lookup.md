# Record lookup in ARCHi

This increment connects Hampton's representation-measurement work to one explicit everyday task in the existing Memories workspace. It does not add another companion, memory database, or chat model route.

## Use

Keep a text source containing a small table, then select it in **Memories → Record lookup**. Select a record and field. ARCHi returns the exact stored value, or asks for a source when that field is absent. A visit-only example is available without saving sample records into personal memory.

```text
record | field | value
PROJECT_A | owner | Alex
PROJECT_A | deadline | 2026-10-04
PROJECT_B | owner | Morgan
PROJECT_B | status | pending
```

The first version accepts exactly two record IDs, a fixed field vocabulary and short ASCII values. Duplicate record/field entries and ambiguous tables are refused. It does not extract authoritative facts from prose. A value being present establishes only what that source says.

**Measure locally** optionally runs one read-only Qwen prefill on the selected question and table. It generates no answer and uses no paid API. Source lookup works independently of this optional operation. Changing source, field, companion or view invalidates a pending measurement.

## How the reader contributes

The frozen reader measures the final prompt residual `h` at `l_out-31` of the pinned Q4_K_M Qwen3.5 9B model. Its direction `v`, center `c`, calibration offset `b`, and scale `s` give:

```text
raw = dot(v, h - c)
standardized = (raw - b) / s
```

The signal was fitted for whether an exact requested field is supplied in a synthetic two-record prompt. It is not a probability, an assessment of a person, or evidence that a value is true. Everyday records represent an unqualified transfer distribution even when they satisfy the same input format. No positive score can fill a missing field, override a source correction, certify a skill, or change a quotient state.

The existing source ID/revision/digest owns the displayed answer. The request ID, prompt digest, model/reader identities and token position own the measurement. These are different evidence objects. Only a current source snapshot can be displayed after the asynchronous operation completes.

## Frozen basis and runtime

- Reader: `archi-task-reader-bundle/v1`, SHA-256 `b699deda8bc7bdd99b5e362c88d16accdd66c163222e89647086b44a680a7ac0`.
- Scope: `synthetic-record-field-support/prompt-final/ridge-v1`.
- Model blob: `dec52a44569a2a25341c4e4d3fee25846eed4f6f0b936278e3a3c900bb99d37c`.
- Backend mathematics: `llama.cpp:161755f29+archi-qwen35-text-v1`.
- New transport: `archi-record-measurement-request/v1` → `archi-record-measurement-result/v1`. One prompt, at most 512 input tokens, zero new tokens, 180-second deadline; only scalar measurements cross back into the native app.

The original bundle's `nativeImportable: false` remains unchanged: it is not admitted into the ordinary reply adapter. The separate record consumer admits only these exact frozen bytes. General chat measurement and steering stay disabled.

The task worker is rebuilt from the source addition while reusing the exact hash-verified mathematical libraries from the qualified acquisition runtime. Its manifest records the changed worker and supported protocol. Both runtime packaging and the native task consumer verify their respective identities. The earlier synthetic qualification remains a historical result, not a new qualification claim for arbitrary personal notes.

## Scope of completion

This is a real native consumer of a measured representation, with source ownership, explicit local execution and cancellation. Hampton's broader learned coupling, closed-loop representation control, transfer qualification, and development consumers remain separate work. The reader does not create evidence for those mechanisms by being installed.

See the [reader mathematics and qualification protocol](../research/representation/gguf/task-reader.md), [retained qualification result](research/task-reader-result-2026-09-26.json), and [system integration map](system-progress-2026-09-26.md).
