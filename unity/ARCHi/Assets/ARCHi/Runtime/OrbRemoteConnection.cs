using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using UnityEngine;
using UnityEngine.Networking;

namespace ARCHi.Port
{
    /// <summary>Optional headset transport. Pairing credentials are runtime-only and never serialized into a scene.</summary>
    [RequireComponent(typeof(OrbSpatialPresenter))]
    public sealed class OrbRemoteConnection : MonoBehaviour
    {
        private OrbSpatialPresenter presenter;
        private string endpoint, token, session, pin;
        private Coroutine polling;
        private readonly HashSet<UnityWebRequest> requests = new HashSet<UnityWebRequest>();
        private bool sending, connected;
        private long sequence;
        private double serverClock;
        private float lastSuccess;
        public string Status { get; private set; } = "Pair with the current ARCHi orb session.";

        public void Connect(string url, string certificateSHA256, string pairingToken, string sessionID)
        {
            Disconnect();
            if (!Uri.TryCreate(url, UriKind.Absolute, out var address) || address.Scheme != "https"
                || !string.IsNullOrEmpty(address.UserInfo) || address.AbsolutePath != "/"
                || !string.IsNullOrEmpty(address.Query) || !string.IsNullOrEmpty(address.Fragment)
                || !IsHex(certificateSHA256) || !IsHex(pairingToken) || !Guid.TryParse(sessionID, out _))
            { Status = "Pairing settings were rejected."; return; }
            presenter = GetComponent<OrbSpatialPresenter>();
            presenter.ResetSession();
            endpoint = address.GetLeftPart(UriPartial.Authority); pin = certificateSHA256.ToLowerInvariant();
            token = pairingToken; session = sessionID; sequence = 0;
            connected = true;
            polling = StartCoroutine(Poll());
        }

        private IEnumerator Poll()
        {
            var interval = new WaitForSecondsRealtime(.5f);
            while (connected)
            {
                using (var request = Request("/presentation", "GET"))
                {
                    yield return request.SendWebRequest();
                    double now = 0;
                    bool valid = request.result == UnityWebRequest.Result.Success
                        && request.downloadHandler.data.Length <= NativePresentationSnapshot.MaximumBytes
                        && double.TryParse(request.GetResponseHeader("X-ARCHi-Time"), NumberStyles.Float, CultureInfo.InvariantCulture, out now)
                        && !double.IsNaN(now) && !double.IsInfinity(now);
                    if (valid)
                    {
                        try { valid = presenter.Apply(new UTF8Encoding(false, true).GetString(request.downloadHandler.data), session, now); }
                        catch (Exception error) when (error is ArgumentException || error is InvalidOperationException)
                        { valid = false; }
                    }
                    if (valid)
                    {
                        serverClock = now; lastSuccess = Time.realtimeSinceStartup;
                        if (long.TryParse(request.GetResponseHeader("X-ARCHi-Next-Sequence"), out var next)) sequence = Math.Max(sequence, next - 1);
                        Status = "Following ARCHi’s current orb session.";
                    }
                    else { presenter.Suspend(); Status = "Connection unavailable. Room overlays were removed."; }
                    requests.Remove(request);
                }
                if (presenter.Current != null && Time.realtimeSinceStartup - lastSuccess < 5)
                    yield return Acknowledge();
                yield return interval;
            }
        }

        [Serializable] private sealed class Acknowledgment
        {
            public int schemaVersion = 1;
            public string sessionID, originDigest, body, appearance, seedAppearance, seedColor, seedAssetSHA256, bodyAssetSHA256;
            public string staffPalette, staffCrown, sessionKind, destination, currentArea = "companion", renderer = "unity-companion";
            public long revision, destinationRevision;
            public double updatedAtUnix;
            public bool active;
            public OrbPresentation orb;
        }
        private IEnumerator Acknowledge()
        {
            var value = presenter.Current;
            if (value?.orb == null || !presenter.Ready) yield break;
            var ack = new Acknowledgment { sessionID = session, originDigest = value.originDigest, revision = value.revision,
                body = value.body, appearance = value.Appearance, seedAppearance = value.SeedAppearance, seedColor = value.SeedColor,
                seedAssetSHA256 = value.seedAssetSHA256, bodyAssetSHA256 = value.bodyAssetSHA256,
                staffPalette = value.staffPalette, staffCrown = value.staffCrown, sessionKind = value.SessionKind,
                destination = value.Destination, destinationRevision = value.destinationRevision, updatedAtUnix = ServerNow,
                active = value.active && value.visible, orb = value.orb };
            using (var request = Request("/ack", "POST", JsonUtility.ToJson(ack))) {
                yield return request.SendWebRequest();
                requests.Remove(request);
            }
        }

        public bool RequestAction(string action, string value = null)
        {
            var current = presenter?.Current;
            if (!connected || sending || current?.orb == null || Time.realtimeSinceStartup - lastSuccess >= 5
                || !current.active || !current.visible) return false;
            bool allowed = action == "theme" ? OrbPresentation.IsTheme(value)
                : action == "anchor" ? value == "world" || value == "follow"
                : (action == "assistant" || action == "memory" || action == "qimon" || action == "arena") && string.IsNullOrEmpty(value);
            if (!allowed) return false;
            var payload = new OrbActionRequest { sessionID = session, originDigest = current.originDigest, revision = current.revision,
                sequence = ++sequence, updatedAtUnix = ServerNow, action = action, value = value };
            sending = true; StartCoroutine(SendAction(JsonUtility.ToJson(payload))); return true;
        }
        private IEnumerator SendAction(string json)
        {
            using (var request = Request("/request", "POST", json))
            {
                yield return request.SendWebRequest();
                Status = request.result == UnityWebRequest.Result.Success
                    ? "Request delivered for ARCHi to check." : "Request delivery was not confirmed. It was not retried.";
                requests.Remove(request);
            }
            sending = false;
        }
        private double ServerNow => serverClock + Mathf.Max(0, Time.realtimeSinceStartup - lastSuccess);
        private UnityWebRequest Request(string route, string method, string body = null)
        {
            var request = new UnityWebRequest(endpoint + route, method) { timeout = 3,
                downloadHandler = new DownloadHandlerBuffer(), certificateHandler = new PinnedCertificate(pin) };
            request.SetRequestHeader("Authorization", "Bearer " + token);
            if (body != null)
            {
                request.uploadHandler = new UploadHandlerRaw(Encoding.UTF8.GetBytes(body));
                request.SetRequestHeader("Content-Type", "application/json");
            }
            requests.Add(request);
            return request;
        }
        private static bool IsHex(string value)
        {
            if (value == null || value.Length != 64) return false;
            foreach (char c in value) if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return false;
            return true;
        }
        private sealed class PinnedCertificate : CertificateHandler
        {
            private readonly byte[] expected;
            public PinnedCertificate(string hex)
            {
                expected = new byte[32];
                for (int i = 0; i < expected.Length; i++) expected[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
            }
            protected override bool ValidateCertificate(byte[] certificateData)
            {
                if (certificateData == null || certificateData.Length == 0) return false;
                using (var sha = SHA256.Create())
                {
                    var actual = sha.ComputeHash(certificateData); int mismatch = 0;
                    for (int i = 0; i < expected.Length; i++) mismatch |= expected[i] ^ actual[i];
                    return mismatch == 0;
                }
            }
        }
        public void Disconnect()
        {
            connected = false;
            // Abort every owned request, including an action/ACK concurrent with the read poll.
            foreach (var request in requests) request.Abort();
            if (polling != null) StopCoroutine(polling);
            StopAllCoroutines(); polling = null; sending = false;
            foreach (var request in requests) request.Dispose();
            requests.Clear();
            presenter?.Suspend(); token = pin = endpoint = session = null;
            Status = "Orb connection stopped.";
        }
        private void OnApplicationPause(bool paused) { if (paused) Disconnect(); }
        private void OnDisable() { Disconnect(); }
    }
}
