using System;
using System.Collections.Generic;
using UnityEngine;

namespace ARCHi.Port
{
    /// <summary>Existing authored KIN rig presented alone. Native owns form; animation owns no progression.</summary>
    public sealed class KinEvolutionStage : MonoBehaviour
    {
        private const int ArtLayer = 28;
        private readonly List<Material> materials = new List<Material>();
        private Camera stageCamera;
        private Transform modelRoot, leftArm, rightArm, crest;
        private GameObject authoredModel;
        private AnimationClip restClip, listenClip, pointClip, currentClip;
        private bool usesAuthoredClips;
        private Quaternion leftRest, rightRest, crestRest;
        private SkinnedMeshRenderer[] shapes;
        private Vector2[] unfoldWindows;
        private Renderer[] renderers;
        private readonly List<Renderer> facialDetails = new List<Renderer>();
        private Material bodyMaterial;
        private float clock, from, target, transitionStart, progress;
        private bool staticMotion = true;
        public RenderTexture Texture { get; private set; }
        public float Progress => progress;
        public bool IsAnimating => !staticMotion && progress != target;
        public int ShapeCount => shapes == null ? 0 : shapes.Length;
        public bool HasAuthoredClips => restClip != null && listenClip != null && pointClip != null;
        public string CurrentClipName => currentClip == null ? "Procedural KIN rest" : currentClip.name;

        public void Initialize(string appearance = "kin")
        {
            if (stageCamera != null) return;
            bool proto = appearance == "proto";
            var asset = Resources.Load<GameObject>(proto ? "Proto/proto-character" : "KIN/kin-arena-motion-v1");
            var shader = Resources.Load<Shader>("KIN/KinLivingJewel");
            var bodyShader = proto ? Resources.Load<Shader>("Proto/ProtoLight") : shader;
            if (asset == null || shader == null || bodyShader == null) throw new InvalidOperationException("The authored KIN rig or material is unavailable.");
            var wrapper = new GameObject("KIN authored body");
            wrapper.transform.SetParent(transform, false);
            modelRoot = wrapper.transform;
            modelRoot.localRotation = Quaternion.Euler(0, 180, 0);
            var model = Instantiate(asset, modelRoot, false);
            authoredModel = model;
            usesAuthoredClips = proto;
            if (proto)
            {
                var animator = model.GetComponent<Animator>();
                if (animator == null) animator = model.AddComponent<Animator>();
                animator.applyRootMotion = false;
                animator.cullingMode = AnimatorCullingMode.AlwaysAnimate;
                foreach (var clip in Resources.LoadAll<AnimationClip>("Proto/proto-character"))
                {
                    if ((clip.name == "Rest" || clip.name.EndsWith("|Rest", StringComparison.Ordinal))) restClip = clip;
                    if ((clip.name == "Listen" || clip.name.EndsWith("|Listen", StringComparison.Ordinal))) listenClip = clip;
                    if ((clip.name == "Point" || clip.name.EndsWith("|Point", StringComparison.Ordinal))) pointClip = clip;
                }
                currentClip = restClip;
            }
            bodyMaterial = CreateMaterial(bodyShader, proto ? "Proto aqua light" : "KIN crimson body",
                proto ? new Color(.18f, .76f, .67f, .55f) : new Color(.3f, .027f, .075f),
                proto ? new Color(.55f, 1, .89f) : new Color(1, .52f, .2f));
            bodyMaterial.SetFloat("_Metallic", proto ? .08f : .14f);
            bodyMaterial.SetFloat("_Glossiness", .60f);
            bodyMaterial.SetColor("_EmissionColor", proto ? new Color(.018f,.055f,.045f) : new Color(.038f,.006f,.014f));
            var pearl = CreateMaterial(shader, "KIN constant heart", new Color(.95f, .85f, .66f), new Color(1, .86f, .65f));
            pearl.SetFloat("_Metallic", .04f);
            pearl.SetColor("_EmissionColor", new Color(.38f, .29f, .15f));
            var gold = CreateMaterial(shader, "KIN golden filaments", new Color(.58f, .32f, .095f), new Color(1, .65f, .28f));
            gold.SetFloat("_Metallic", .48f);
            gold.SetColor("_EmissionColor", new Color(.12f,.065f,.012f));
            foreach (var child in model.GetComponentsInChildren<Transform>())
            {
                child.gameObject.layer = ArtLayer;
                if (child.name == "Arm.L") leftArm = child;
                if (child.name == "Arm.R") rightArm = child;
                if (child.name == "Crest") crest = child;
            }
            leftRest = leftArm == null ? Quaternion.identity : leftArm.localRotation;
            rightRest = rightArm == null ? Quaternion.identity : rightArm.localRotation;
            crestRest = crest == null ? Quaternion.identity : crest.localRotation;
            shapes = model.GetComponentsInChildren<SkinnedMeshRenderer>();
            unfoldWindows = new Vector2[shapes.Length];
            for (int i = 0; i < shapes.Length; i++)
            {
                var part = shapes[i].name.ToLowerInvariant();
                // Authored animation paths stay intact. Only KIN's retained CompactSeed morphs
                // use a layered presentation front; Proto keeps its existing clip-driven rig.
                unfoldWindows[i] = proto ? new Vector2(0,1)
                    : part.Contains("crest") ? new Vector2(.34f,1)
                    : part.Contains("arm") ? new Vector2(.22f,.95f)
                    : part.Contains("grounded") || part.Contains("foot") ? new Vector2(.14f,.88f)
                    : new Vector2(.04f,.82f);
            }
            renderers = model.GetComponentsInChildren<Renderer>();
            var eyeInk = proto ? CreateMaterial(shader, "Proto violet eyes", new Color(.012f, .018f, .085f), new Color(.35f, .2f, .7f)) : null;
            var mint = proto ? CreateMaterial(shader, "Proto mint details", new Color(.16f, .6f, .51f), new Color(.5f, 1, .88f)) : null;
            foreach (var renderer in renderers)
            {
                var name = renderer.name.ToLowerInvariant();
                if (name.Contains("eye") || name.Contains("smile")) facialDetails.Add(renderer);
                if (proto)
                {
                    renderer.sharedMaterial = name.Contains("heart") || name.Contains("core") || name.Contains("glint") ? pearl
                        : name.Contains("pupil") || name.Contains("smile") || (name.Contains("eye") && !name.Contains("rim")) ? eyeInk
                        : name.Contains("mote") || name.Contains("rim") || name.Contains("inner leaf") ? mint : bodyMaterial;
                    continue;
                }
                renderer.sharedMaterial = name.Contains("heart") || name.Contains("core") || name.Contains("eye") ? pearl
                    : name.Contains("current") || name.Contains("brow") || name.Contains("smile") ? gold : bodyMaterial;
            }
            AddLight("KIN warm key", new Color(1, .86f, .72f), 1.05f, new Vector3(32, -32, 0));
            AddLight("KIN cool rim", new Color(.40f, .78f, 1), .82f, new Vector3(24, 154, 0));
            AddLight("KIN soft face fill", new Color(.70f, .78f, 1), .30f, new Vector3(-10, 26, 0));
            var cameraObject = new GameObject("Native evolution presentation camera");
            cameraObject.transform.SetParent(transform, false);
            stageCamera = cameraObject.AddComponent<Camera>();
            stageCamera.cullingMask = 1 << ArtLayer;
            stageCamera.clearFlags = CameraClearFlags.SolidColor;
            stageCamera.backgroundColor = Color.clear;
            stageCamera.allowHDR = true;
            stageCamera.allowMSAA = true;
            stageCamera.orthographic = true;
            stageCamera.orthographicSize = 1.95f;
            stageCamera.transform.localPosition = new Vector3(0, 1.6f, -7);
            stageCamera.transform.localRotation = Quaternion.identity;
            stageCamera.nearClipPlane = .1f;
            stageCamera.farClipPlane = 20;
            Texture = new RenderTexture(768, 768, 24, RenderTextureFormat.ARGBHalf) { name = "KIN native evolution presentation", antiAliasing = 2 };
            Texture.Create();
            stageCamera.targetTexture = Texture;
            var finish = cameraObject.AddComponent<ArenaBloom>();
            finish.PreserveAlpha = true;
            finish.Strength = .12f;
            finish.Threshold = .95f;
            finish.Exposure = 1.05f;
            finish.Vignette = 0;
            // Explicit rendering avoids an idle camera consuming frames when Seed is shown.
            stageCamera.enabled = false;
            RenderPose();
        }

        public void Apply(bool firstLight, bool freeze, string lightMode, bool animateTransition)
        {
            var next = firstLight ? 1f : 0f;
            if (next != target)
            {
                from = progress;
                target = next;
                transitionStart = Time.unscaledTime;
                if (freeze || !animateTransition) { progress = target; from = target; transitionStart = Time.unscaledTime - 2.4f; }
            }
            staticMotion = freeze;
            if (usesAuthoredClips)
            {
                var nextClip = lightMode == "focus" ? pointClip : lightMode == "orbit" || lightMode == "pulse" ? listenClip : restClip;
                if (nextClip != currentClip) clock = 0;
                currentClip = nextClip;
            }
            if (freeze) { progress = target; from = target; transitionStart = Time.unscaledTime - 2.4f; }
            var color = lightMode == "focus" ? new Color(.3f, .9f, .84f)
                : lightMode == "orbit" ? new Color(.72f, .52f, 1)
                : lightMode == "pulse" ? new Color(1, .56f, .67f)
                : lightMode == "delight" ? new Color(.48f, 1, .76f)
                : new Color(1, .65f, .28f);
            bodyMaterial.SetColor("_RimColor", color);
            RenderPose();
        }

        public void Tick(bool visible)
        {
            if (stageCamera == null || !visible || (staticMotion && progress == target)) return;
            clock += Mathf.Min(Time.unscaledDeltaTime, .1f);
            if (!staticMotion) progress = Mathf.Lerp(from, target, Mathf.SmoothStep(0, 1, Mathf.Clamp01((Time.unscaledTime - transitionStart) / 2.4f)));
            RenderPose();
        }

        private void RenderPose()
        {
            float breath = staticMotion ? 0 : Mathf.Sin(clock * 1.6f);
            float unfolding = IsAnimating ? Mathf.Sin(Mathf.PI * progress) : 0;
            modelRoot.localPosition = new Vector3(0, breath * .018f + unfolding * .025f, 0);
            if (currentClip != null && authoredModel != null)
                currentClip.SampleAnimation(authoredModel, staticMotion ? (currentClip == pointClip ? currentClip.length * .5f : 0) : Mathf.Repeat(clock, currentClip.length));
            if (!usesAuthoredClips && leftArm != null) leftArm.localRotation = leftRest * Quaternion.Euler(0, breath * 2 + unfolding * 8, 0);
            if (!usesAuthoredClips && rightArm != null) rightArm.localRotation = rightRest * Quaternion.Euler(0, -breath * 2 - unfolding * 8, 0);
            if (!usesAuthoredClips && crest != null) crest.localRotation = crestRest * Quaternion.Euler(0, 0, breath * 1.5f - unfolding * 3);
            for (int i = 0; i < shapes.Length; i++)
            {
                if (shapes[i].sharedMesh.blendShapeCount == 0) continue;
                var window = unfoldWindows[i];
                float amount = usesAuthoredClips ? progress : Mathf.SmoothStep(0,1,Mathf.InverseLerp(window.x,window.y,progress));
                shapes[i].SetBlendShapeWeight(0, 100 * (1 - amount));
            }
            foreach (var detail in facialDetails) detail.enabled = progress > .64f;
            bodyMaterial.SetFloat("_Evolving", IsAnimating ? 1 : 0);
            bodyMaterial.SetFloat("_ScanY", Mathf.Lerp(2.6f, .1f, progress));
            if (bodyMaterial.HasProperty("_Pulse")) bodyMaterial.SetFloat("_Pulse", staticMotion ? 0 : Mathf.Max(0,breath)*.25f);
            stageCamera.Render();
        }

        private Material CreateMaterial(Shader shader, string label, Color color, Color rim)
        {
            var material = new Material(shader) { name = label };
            material.SetColor("_Color", color);
            material.SetColor("_RimColor", rim);
            material.SetFloat("_Metallic", .16f);
            material.SetFloat("_Glossiness", .64f);
            materials.Add(material);
            return material;
        }
        private void AddLight(string label, Color color, float intensity, Vector3 angle)
        {
            var item = new GameObject(label);
            item.transform.SetParent(transform, false);
            item.transform.localRotation = Quaternion.Euler(angle);
            var light = item.AddComponent<Light>();
            light.type = LightType.Directional;
            light.color = color;
            light.intensity = intensity;
            light.cullingMask = 1 << ArtLayer;
        }
        private void OnDestroy()
        {
            if (stageCamera != null) stageCamera.targetTexture = null;
            if (Texture != null) { Texture.Release(); Destroy(Texture); }
            foreach (var material in materials) Destroy(material);
        }
    }
}
