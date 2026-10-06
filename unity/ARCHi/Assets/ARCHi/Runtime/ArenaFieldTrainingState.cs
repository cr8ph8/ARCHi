using System;

namespace ARCHi.Port
{
    public enum ArenaParticipantKind { Companion, Npc }
    public enum FieldTrainingEvolutionState { Untrained, Practicing, FieldEvidenceReady }

    /// <summary>Field-specific facts extracted from the same simultaneous Arena rules for either seat.</summary>
    public sealed class ArenaFieldTrainingFacts
    {
        public ArenaField Field { get; }
        public ArenaMove Move { get; }
        public int ProtectedDamage { get; }
        public int DamageTaken { get; }
        public int DamageDealt { get; }
        public bool AppliedExposure { get; }

        internal ArenaFieldTrainingFacts(ArenaField field, ArenaMove move, int protection, int taken, int dealt, bool exposure)
        { Field = field; Move = move; ProtectedDamage = protection; DamageTaken = taken; DamageDealt = dealt; AppliedExposure = exposure; }
    }

    /// <summary>Only ArenaRehearsal resolution creates these; callers cannot supply invented hit statistics.</summary>
    public sealed class ArenaCombatRound
    {
        internal ArenaRehearsal Bout { get; }
        public int Round { get; }
        private readonly ArenaFieldTrainingFacts one, two;
        internal ArenaCombatRound(ArenaRehearsal bout, int round, ArenaFieldTrainingFacts one, ArenaFieldTrainingFacts two)
        { Bout = bout; Round = round; this.one = one; this.two = two; }
        public ArenaFieldTrainingFacts For(ArenaSeat seat)
        {
            if (!Enum.IsDefined(typeof(ArenaSeat), seat)) throw new ArgumentOutOfRangeException(nameof(seat));
            return seat == ArenaSeat.One ? one : two;
        }
    }

    /// <summary>
    /// Disposable contact-backed field evidence, never native evolution or a saved body.
    /// Threshold 1 preserves ArenaExperience's existing greater-than-zero candidate test.
    /// A completed replay and explicit Review remain separate from crossing this threshold.
    /// </summary>
    public sealed class ArenaFieldTrainingState
    {
        public const int EvidenceThreshold = 1;
        public ArenaField Field { get; }
        public int AcceptedContacts { get; private set; }
        public int ProtectedRounds { get; private set; }
        public int ExposureApplications { get; private set; }
        public int ProtectedDamage { get; private set; }
        public int DamageTaken { get; private set; }
        public int DamageDealt { get; private set; }
        public int LastAcceptedRound { get; private set; }
        public bool CanGrantEvolution => false;
        public FieldTrainingEvolutionState EvolutionState =>
            (Field == ArenaField.Guardian ? ProtectedRounds : ExposureApplications) >= EvidenceThreshold
                ? FieldTrainingEvolutionState.FieldEvidenceReady
                : AcceptedContacts > 0 ? FieldTrainingEvolutionState.Practicing : FieldTrainingEvolutionState.Untrained;

        internal ArenaFieldTrainingState(ArenaField field) { Field = field; }
        internal bool Record(ArenaCombatRound round, ArenaSeat seat)
        {
            if (round == null || round.Round <= LastAcceptedRound) return false;
            var facts = round.For(seat);
            if (facts.Field != Field) return false;
            LastAcceptedRound = round.Round;
            AcceptedContacts++;
            if (facts.ProtectedDamage > 0) ProtectedRounds++;
            if (facts.AppliedExposure) ExposureApplications++;
            ProtectedDamage += facts.ProtectedDamage;
            DamageTaken += facts.DamageTaken;
            DamageDealt += facts.DamageDealt;
            return true;
        }
    }
}
