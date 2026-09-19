using System;

namespace ARCHi.Port
{
    /// <summary>Presentation-only counterpart of native KinSeedMotion: 80s turn, 0.6s focus settling.</summary>
    public sealed class KinSeedPresentationMotion
    {
        public const double RevolutionDuration = 80;
        public const double MaximumSpeed = 360 / RevolutionDuration;
        public const double SettlingDuration = .6;
        private double anchorTime, anchorAngle, initialSpeed, targetSpeed, duration;
        private bool initialized;
        private bool reduced, settles;
        public void Apply(string lightMode, bool staticMotion, double time)
        {
            bool nextSettles = lightMode == "focus" || lightMode == "hold";
            double nextSpeed = staticMotion || nextSettles ? 0 : MaximumSpeed;
            if (!initialized)
            {
                initialized = true;
                anchorTime = time;
                initialSpeed = targetSpeed = nextSpeed;
            }
            if (reduced == staticMotion && settles == nextSettles && targetSpeed == nextSpeed) return;
            var sample = Sample(time);
            anchorAngle = sample.angle;
            anchorTime = time;
            initialSpeed = staticMotion ? 0 : sample.speed;
            targetSpeed = nextSpeed;
            duration = staticMotion || initialSpeed == targetSpeed ? 0 : SettlingDuration;
            reduced = staticMotion;
            settles = nextSettles;
        }
        public (double angle, double speed) Sample(double time)
        {
            double elapsed = !double.IsNaN(time) && !double.IsInfinity(time) && time >= anchorTime ? time - anchorTime : 0;
            double ramp = Math.Min(elapsed, duration), f = duration > 0 ? ramp / duration : 1, square = f * f;
            double speed = initialSpeed + (targetSpeed - initialSpeed) * square * (3 - 2 * f);
            double rampAngle = initialSpeed * ramp + (targetSpeed - initialSpeed) * duration * (square * f - square * square / 2);
            double steady = Math.Max(0, elapsed - duration) % RevolutionDuration;
            return ((anchorAngle + rampAngle + targetSpeed * steady) % 360, Math.Min(MaximumSpeed, Math.Max(0, speed)));
        }
    }
}
