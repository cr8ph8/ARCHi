using UnityEngine;

namespace ARCHi.Port
{
    /// <summary>A single-use physics receipt for an already resolved attack; it does not apply damage.</summary>
    [DisallowMultipleComponent, RequireComponent(typeof(Rigidbody))]
    public sealed class ArenaCombatContact : MonoBehaviour
    {
        private ArenaFieldTrainingBody source, target;
        private ArenaCombatRound round;
        private bool consumed;
        private int sourceBinding, targetBinding;
        public bool Consumed => consumed;

        public bool Arm(ArenaFieldTrainingBody attacker, ArenaFieldTrainingBody recipient)
        {
            // An object is single-use. Re-arming cannot replay an old receipt after pooling.
            if (round != null || attacker == null || recipient == null || attacker == recipient
                || attacker.Seat == recipient.Seat || !ReferenceEquals(attacker.Bout, recipient.Bout)) return false;
            var next = attacker.Bout?.LastCombatRound;
            if (next == null || !attacker.CanReceive(next) || !recipient.CanReceive(next)
                || next.For(attacker.Seat).Move == ArenaMove.Guard) return false;
            source = attacker; target = recipient; round = next;
            sourceBinding = source.BindingVersion; targetBinding = target.BindingVersion;
            return true;
        }

        internal void TryConsume(ArenaFieldTrainingBody recipient)
        {
            if (!isActiveAndEnabled || consumed || round == null || recipient != target
                || source == null || target == null || source.BindingVersion != sourceBinding || target.BindingVersion != targetBinding
                || !source.CanReceive(round) || !target.CanReceive(round)) return;
            consumed = true;
            // Both participants observe the same resolved contact. Two simultaneous
            // attack colliders still contribute at most one round per participant.
            var targetState = target.State; var sourceState = source.State;
            var targetChanged = target.Record(round);
            var sourceChanged = source.Record(round);
            // Commit both participants before notifying. A listener may reset the
            // bout, disable a body or destroy an actor; stale notifications then stop.
            if (targetChanged && target != null) target.NotifyEvolutionChanged(targetState, targetBinding);
            if (sourceChanged && source != null) source.NotifyEvolutionChanged(sourceState, sourceBinding);
        }
    }
}
