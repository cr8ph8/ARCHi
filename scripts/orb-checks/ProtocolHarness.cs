// Headless protocol test adapter only. This is not a replacement for Unity serialization or rendering QA.
using System;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization.Metadata;

ARCHi.Port.Editor.OrbPresentationChecks.Run();

namespace UnityEngine
{
    public static class Debug { public static void Log(object value) => Console.WriteLine(value); }
    public static class JsonUtility
    {
        private static readonly JsonSerializerOptions Options = CreateOptions();
        private static JsonSerializerOptions CreateOptions()
        {
            var resolver = new DefaultJsonTypeInfoResolver();
            resolver.Modifiers.Add(info => {
                for (int i = info.Properties.Count - 1; i >= 0; i--)
                    if (info.Properties[i].AttributeProvider is FieldInfo field && field.IsNotSerialized)
                        info.Properties.RemoveAt(i);
            });
            return new JsonSerializerOptions { IncludeFields = true, IgnoreReadOnlyProperties = true, TypeInfoResolver = resolver };
        }
        public static T FromJson<T>(string json)
        {
            try { return JsonSerializer.Deserialize<T>(json, Options); }
            catch (JsonException error) { throw new ArgumentException("Malformed JSON", error); }
        }
        public static string ToJson(object value) => JsonSerializer.Serialize(value, value.GetType(), Options);
    }
}

namespace ARCHi.Port
{
    // The headless cases are descriptor-free except for orb. Point packages remain independently tested in Unity/native.
    public static class LiminalPointAsset
    {
        public static void RejectDuplicateKeys(string json)
        {
            try { using var doc = JsonDocument.Parse(json); Inspect(doc.RootElement); }
            catch (JsonException error) { throw new ArgumentException("Malformed JSON", error); }
        }
        private static void Inspect(JsonElement element)
        {
            if (element.ValueKind == JsonValueKind.Object)
            {
                var keys = new System.Collections.Generic.HashSet<string>();
                foreach (var property in element.EnumerateObject())
                {
                    if (!keys.Add(property.Name)) throw new System.IO.InvalidDataException("Repeated key");
                    Inspect(property.Value);
                }
            }
            else if (element.ValueKind == JsonValueKind.Array) foreach (var child in element.EnumerateArray()) Inspect(child);
        }
    }
    [Serializable] public sealed class NativePointPresentation
    {
        public bool IsValid(NativePresentationSnapshot value) => false;
        public static bool Same(NativePointPresentation a, NativePointPresentation b) => ReferenceEquals(a, b);
    }
    [Serializable] public sealed class LiminalPointStructure
    {
        public string Digest => null;
        public static bool TryRead(string json, NativePresentationSnapshot value, out LiminalPointStructure result) { result = null; return false; }
    }
    public static class LiminalPointFinish { public const string ExpectedManifestSHA256 = "finish-fixture-unused"; }
    public static class LiminalParticleRenderer { public const string LightStyleRevision = "light-fixture-unused"; }
}
