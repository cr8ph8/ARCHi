import { choosePracticeCommand, type BattleState, type BattleTeamId } from "./battle-engine";
import { listBattleChoices, type BattleChoice } from "./battle-presentation";
import type { Journey } from "./model";
import { projectQiMonRoster, qiMonMemorySources, QIMON_MEMORY_CONTEXT,
  type QiMonRoster, type QiMonMemoryInfluence } from "./qimon-roster";

export interface MemoryInfluenceInput {
  readonly sourceID: string;
  readonly eligible: boolean;
  readonly contextMatch: number;
  readonly retrievalSalience: number;
  readonly polarity: -1 | 0 | 1 | null;
  readonly magnitude: number;
  readonly confidence: number;
}

export interface MemoryInfluenceRow extends MemoryInfluenceInput {
  readonly retrieval: number;
  readonly weight: number;
  readonly contribution: number;
}

export interface MemoryInfluenceEvaluation {
  readonly rows: readonly MemoryInfluenceRow[];
  readonly influence: number;
  readonly positiveMass: number;
  readonly negativeMass: number;
  readonly neutralMass: number;
  readonly assessedCount: number;
  readonly unassessedCount: number;
}

/** Pure bounded scoring. Polarity, confidence and magnitude never alter retrieval. */
export function evaluateMemoryInfluence(inputs: readonly MemoryInfluenceInput[]): MemoryInfluenceEvaluation {
  if (!Array.isArray(inputs) || inputs.length > 256) throw new Error("Memory influence input exceeds its bounded budget.");
  const origins = new Set<string>();
  const rows = inputs.map((input) => {
    if (!input || typeof input.sourceID !== "string" || !input.sourceID || input.sourceID.length > 256
        || origins.has(input.sourceID) || typeof input.eligible !== "boolean"
        || ![null, -1, 0, 1].includes(input.polarity)
        || ![input.contextMatch, input.retrievalSalience, input.magnitude, input.confidence]
          .every((number) => typeof number === "number" && Number.isFinite(number) && number >= 0 && number <= 1)) {
      throw new Error("Memory influence needs unique source origins and valid bounded assessments.");
    }
    origins.add(input.sourceID);
    const retrieval = input.eligible ? input.contextMatch * input.retrievalSalience : 0;
    const weight = input.eligible && input.polarity !== null ? retrieval * input.confidence * input.magnitude : 0;
    return Object.freeze({ ...input, retrieval, weight, contribution: weight * (input.polarity ?? 0) });
  });
  const mass = (polarity: -1 | 0 | 1): number => rows.reduce((sum, row) => sum + (row.polarity === polarity ? row.weight : 0), 0);
  const positiveMass = mass(1), negativeMass = mass(-1), neutralMass = mass(0);
  return Object.freeze({ rows: Object.freeze(rows), positiveMass, negativeMass, neutralMass,
    influence: (positiveMass - negativeMass) / (1 + positiveMass + negativeMass + neutralMass),
    assessedCount: rows.filter((row) => row.eligible && row.polarity !== null).length,
    unassessedCount: rows.filter((row) => row.eligible && row.polarity === null).length });
}

export interface QiMonMemoryRankedChoice extends BattleChoice {
  readonly baseScore: number;
  readonly score: number;
  readonly memory: MemoryInfluenceEvaluation;
  readonly assessments: readonly QiMonMemoryInfluence[];
}

/**
 * Revalidates the live Journey/roster before ranking only lawful public-state moves.
 * These are player recommendations. The unchanged battle reducer still validates
 * an explicitly selected command; this function neither plays nor keeps a move.
 */
export function rankQiMonPracticeChoices(state: BattleState, teamId: BattleTeamId,
  journey: Journey, roster: QiMonRoster): readonly QiMonMemoryRankedChoice[] {
  const projection = projectQiMonRoster(journey, roster);
  const team = state.teams.find((candidate) => candidate.id === teamId);
  const active = team?.roster.find((member) => member.id === team.activeQiMonId && member.integrity > 0);
  const member = active && projection.members.find((candidate) => candidate.id === active.id
    && candidate.card.role === active.role && candidate.card.name === active.name);
  if (!member || state.status !== "active") return Object.freeze([]);
  const sources = new Map(qiMonMemorySources(journey, roster, member.id).map((source) => [source.eventId, source.digest]));
  const base = choosePracticeCommand(state, teamId);
  const choices = listBattleChoices(state, teamId).map((choice, index) => {
    const assessments = projection.memoryInfluences.filter((assessment) => assessment.memberId === member.id
      && assessment.context === QIMON_MEMORY_CONTEXT && assessment.targetAction === choice.command.action);
    const memory = evaluateMemoryInfluence(assessments.map((assessment): MemoryInfluenceInput => ({
      sourceID: assessment.sourceEventId, eligible: sources.get(assessment.sourceEventId) === assessment.sourceEventSha256,
      contextMatch: 1, retrievalSalience: assessment.retrievalSalience, polarity: assessment.polarity,
      magnitude: assessment.magnitude, confidence: assessment.confidence,
    })));
    // Preserve the public-state policy's preferred move when memory is unassessed.
    const baseScore = choice.command.action === base.action
      && choice.command.targetQiMonId === base.targetQiMonId ? 0.25 : 0;
    return { index, choice: Object.freeze({ ...choice, baseScore, score: baseScore + memory.influence,
      memory, assessments: Object.freeze(assessments) }) };
  });
  choices.sort((left, right) => right.choice.score - left.choice.score || left.index - right.index);
  return Object.freeze(choices.map(({ choice }) => choice));
}
