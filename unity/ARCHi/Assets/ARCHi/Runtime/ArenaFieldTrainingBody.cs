using System;
using UnityEngine;

namespace ARCHi.Port
{
    /// <summary>Attaches session evidence to an NPC or companion's physics body.</summary>
    [DisallowMultipleComponent, RequireComponent(typeof(Rigidbody))]
    public sealed class ArenaFieldTrainingBody : MonoBehaviour
    {
        public ArenaRehearsal Bout { get; private set; }
        public ArenaSeat Seat { get; private set; }
        public ArenaParticipantKind Kind { get; private set; }
        public ArenaFieldTrainingState State { get; private set; }
        public int CollisionCallbacks { get; private set; }
        public int TriggerCallbacks { get; private set; }
        internal int BindingVersion { get; private set; }
        public event Action<ArenaFieldTrainingBody> EvolutionStateChanged;

        public void Bind(ArenaRehearsal bout, ArenaSeat seat, ArenaParticipantKind kind)
        {
            if (bout == null) throw new ArgumentNullException(nameof(bout));
            if (!Enum.IsDefined(typeof(ArenaSeat), seat)) throw new ArgumentOutOfRangeException(nameof(seat));
            if (!Enum.IsDefined(typeof(ArenaParticipantKind), kind)) throw new ArgumentOutOfRangeException(nameof(kind));
            if (ReferenceEquals(Bout, bout) && Seat == seat && Kind == kind) return;
            BindingVersion++;
            Bout = bout; Seat = seat; Kind = kind;
            State = new ArenaFieldTrainingState(seat == ArenaSeat.One ? bout.Field : bout.RivalField);
            CollisionCallbacks = TriggerCallbacks = 0;
        }

        internal bool CanReceive(ArenaCombatRound round)
        {
            return isActiveAndEnabled && State != null && ReferenceEquals(Bout, round?.Bout)
                && ReferenceEquals(Bout.LastCombatRound, round) && round.Round == Bout.Round - 1;
        }
        internal bool Record(ArenaCombatRound round)
        {
            if (!CanReceive(round)) return false;
            var before = State.EvolutionState;
            return State.Record(round, Seat) && before != State.EvolutionState;
        }
        internal void NotifyEvolutionChanged(ArenaFieldTrainingState expectedState, int expectedBinding)
        {
            if (isActiveAndEnabled && BindingVersion == expectedBinding && ReferenceEquals(State, expectedState))
                EvolutionStateChanged?.Invoke(this);
        }
        private void OnDisable(){BindingVersion++;}
        private void OnTriggerEnter(Collider other)
        {
            if (!isActiveAndEnabled) return;
            TriggerCallbacks++;
            Receive(other);
        }
        private void OnCollisionEnter(Collision collision)
        {
            if (!isActiveAndEnabled) return;
            CollisionCallbacks++;
            Receive(collision.collider);
        }
        private void Receive(Collider other)
        {
            // Child colliders resolve through their actual Rigidbody, not arbitrary names or tags.
            var body = other == null ? null : other.attachedRigidbody;
            if (body != null && body.TryGetComponent<ArenaCombatContact>(out var contact)) contact.TryConsume(this);
        }
    }
}
