using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace ARCHi.Port.Editor
{
    /// <summary>Imports the preserved KIN meshes and binds their Blender-baked UV maps.</summary>
    public sealed class FieldTrainingAssetImport : AssetPostprocessor
    {
        private const string Folder = "Assets/Resources/FieldTraining/";
        private const string Stem = "kin-field-training";
        private const string ModelPath = Folder + Stem + ".fbx";
        private const string MaterialPath = Folder + Stem + ".mat";
        private const string PrefabPath = Folder + Stem + "-companion.prefab";

        private void OnPreprocessModel()
        {
            if (assetPath != ModelPath) return;
            var importer = (ModelImporter)assetImporter;
            importer.importBlendShapes = true;
            importer.importAnimation = false;
            importer.importCameras = false;
            importer.importLights = false;
            importer.addCollider = false;
            importer.materialImportMode = ModelImporterMaterialImportMode.None;
            importer.globalScale = 1;
            importer.bakeAxisConversion = false;
            importer.isReadable = true;
        }

        private void OnPreprocessTexture()
        {
            if (!assetPath.StartsWith(Folder + Stem + "-", StringComparison.Ordinal) || !assetPath.EndsWith(".png", StringComparison.Ordinal)) return;
            var importer = (TextureImporter)assetImporter;
            importer.textureType = TextureImporterType.Default;
            importer.sRGBTexture = true;
            importer.alphaSource = TextureImporterAlphaSource.None;
            importer.wrapMode = TextureWrapMode.Clamp;
            importer.filterMode = FilterMode.Bilinear;
            importer.mipmapEnabled = true;
            importer.maxTextureSize = 1024;
            importer.textureCompression = TextureImporterCompression.Uncompressed;
        }

        [MenuItem("ARCHi/Field Training/Import and Validate Authored Assets")]
        public static void Run()
        {
            Debug.Log("Field-training authored asset checks passed: " + ImportAndValidate());
        }

        public static int ImportAndValidate()
        {
            string expectedProject = Environment.GetEnvironmentVariable("ARCHI_FIELD_TRAINING_PROJECT_PATH");
            if (string.IsNullOrWhiteSpace(expectedProject) || !Path.IsPathRooted(expectedProject))
                throw new InvalidOperationException("Set ARCHI_FIELD_TRAINING_PROJECT_PATH to the reviewed absolute Unity project directory before importing authored assets.");
            string expectedAssets = Path.GetFullPath(Path.Combine(expectedProject, "Assets"));
            if (!string.Equals(Path.GetFullPath(Application.dataPath), expectedAssets, StringComparison.Ordinal))
                throw new InvalidOperationException("Field-training import must target the verified ARCHi Unity project: " + expectedAssets);
            if (EditorApplication.isPlayingOrWillChangePlaymode || EditorApplication.isCompiling)
                throw new InvalidOperationException("Stop Play mode and wait for compilation before importing field-training assets.");
            AssetDatabase.ImportAsset(ModelPath, ImportAssetOptions.ForceUpdate | ImportAssetOptions.ForceSynchronousImport);
            AssetDatabase.ImportAsset(Folder + Stem + "-albedo.png", ImportAssetOptions.ForceUpdate | ImportAssetOptions.ForceSynchronousImport);
            AssetDatabase.ImportAsset(Folder + Stem + "-emission.png", ImportAssetOptions.ForceUpdate | ImportAssetOptions.ForceSynchronousImport);
            var model = AssetDatabase.LoadAssetAtPath<GameObject>(ModelPath);
            var albedo = AssetDatabase.LoadAssetAtPath<Texture2D>(Folder + Stem + "-albedo.png");
            var emission = AssetDatabase.LoadAssetAtPath<Texture2D>(Folder + Stem + "-emission.png");
            var shader = Resources.Load<Shader>("Proto/SoftCreature");
            int checks = 0;
            Action<bool, string> check = (passed, description) =>
            {
                if (!passed) throw new InvalidOperationException(description);
                checks++;
            };
            check(model != null && albedo != null && emission != null && shader != null, "Field-training model, baked maps and presentation shader must import.");
            check(shader.isSupported && ShaderUtil.GetShaderMessages(shader).Length == 0, "Mapped presentation shader must be supported with no compiler diagnostics.");
            check(albedo.width == 1024 && albedo.height == 1024 && emission.width == 1024 && emission.height == 1024, "Expected both 1024px source-baked maps.");
            var material = AssetDatabase.LoadAssetAtPath<Material>(MaterialPath);
            if (material == null)
            {
                material = new Material(shader) { name = "KIN authored field-training surface" };
                AssetDatabase.CreateAsset(material, MaterialPath);
            }
            material.shader = shader;
            check(material.HasProperty("_BaseMapStrength"), "Presentation shader must opt into sampling the baked atlas.");
            material.mainTexture = albedo;
            material.SetFloat("_BaseMapStrength", 1);
            check(material.HasProperty("_UseRestCoordinates"), "Presentation shader must keep reveal coordinates separate from the atlas.");
            material.SetFloat("_UseRestCoordinates", 1);
            material.SetColor("_Color", Color.white);
            material.SetFloat("_Glossiness", .28f);
            material.SetColor("_RimColor", new Color(1, .5f, .18f));
            check(material.HasProperty("_EmissionMap") && material.HasProperty("_EmissionMapStrength"), "Presentation shader must support the authored emission map.");
            material.SetTexture("_EmissionMap", emission);
            material.SetFloat("_EmissionMapStrength", 1);
            material.SetFloat("_EmissionMapScale", 4.5f);
            EditorUtility.SetDirty(material);
            GameObject instance = null;
            var previewScene = EditorSceneManager.NewPreviewScene();
            try
            {
                instance = (GameObject)PrefabUtility.InstantiatePrefab(model, previewScene);
                instance.name = "KIN field-training companion";
                var renderers = instance.GetComponentsInChildren<Renderer>(true);
                var meshes = instance.GetComponentsInChildren<MeshFilter>(true).Select(filter => filter.sharedMesh)
                    .Concat(instance.GetComponentsInChildren<SkinnedMeshRenderer>(true).Select(renderer => renderer.sharedMesh)).ToArray();
                check(renderers.Length == 21 && meshes.Length == 21, "All 21 authored meshes must remain.");
                check(meshes.All(mesh => mesh != null && mesh.uv.Length == mesh.vertexCount), "Every imported vertex needs texture coordinates.");
                check(meshes.All(mesh => mesh.uv2.Length == mesh.vertexCount), "Every imported vertex needs separate authored reveal coordinates.");
                check(meshes.Count(mesh => mesh.blendShapeCount > 0) == 17, "All 17 CompactSeed morph meshes must remain.");
                check(meshes.Where(mesh => mesh.blendShapeCount > 0).All(mesh => Enumerable.Range(0, mesh.blendShapeCount).Any(index => mesh.GetBlendShapeName(index).EndsWith("CompactSeed", StringComparison.Ordinal))), "Original CompactSeed morph names must remain.");
                var names = instance.GetComponentsInChildren<Transform>(true).Select(transform => transform.name).ToArray();
                check(new[] { "Arm.L", "Arm.R", "Crest" }.All(names.Contains), "Original arm and crest attachment pivots must remain.");
                foreach (var renderer in renderers) renderer.sharedMaterial = material;
                PrefabUtility.SaveAsPrefabAsset(instance, PrefabPath);
                AssetDatabase.SaveAssetIfDirty(material);
                var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(PrefabPath);
                check(prefab != null && prefab.GetComponentsInChildren<Renderer>(true).All(renderer => renderer.sharedMaterial == material && renderer.sharedMaterial.mainTexture == albedo), "Saved prefab must bind the actual baked albedo map to every renderer.");
                check(prefab.GetComponentsInChildren<Renderer>(true).All(renderer => renderer.sharedMaterial.GetTexture("_EmissionMap") == emission
                    && renderer.sharedMaterial.GetFloat("_BaseMapStrength") == 1 && renderer.sharedMaterial.GetFloat("_EmissionMapStrength") == 1
                    && renderer.sharedMaterial.GetFloat("_EmissionMapScale") == 4.5f), "Saved prefab must bind and enable both authored maps with the correct emission scale.");
                check(prefab.GetComponentsInChildren<Renderer>(true).All(renderer => renderer.sharedMaterial.GetFloat("_UseRestCoordinates") == 1), "Saved prefab must use separate reveal coordinates.");
                var receipt = new ImportReceipt
                {
                    unityVersion = Application.unityVersion, passed = true, checks = checks,
                    meshCount = meshes.Length, morphMeshCount = meshes.Count(mesh => mesh.blendShapeCount > 0),
                    modelPath = ModelPath, prefabPath = PrefabPath, materialPath = MaterialPath,
                    albedoPath = AssetDatabase.GetAssetPath(albedo), emissionPath = AssetDatabase.GetAssetPath(emission)
                };
                var receiptPath = Path.GetFullPath(Path.Combine(Application.dataPath, "../../../desktop/ArtSources/field-training-v1/unity-import.json"));
                File.WriteAllText(receiptPath, JsonUtility.ToJson(receipt, true) + "\n");
            }
            finally
            {
                if (instance != null) UnityEngine.Object.DestroyImmediate(instance);
                EditorSceneManager.ClosePreviewScene(previewScene);
            }
            return checks;
        }

        [Serializable]
        private sealed class ImportReceipt
        {
            public string schema = "archi-field-training-unity-import/v1";
            public string unityVersion;
            public bool passed;
            public int checks;
            public int meshCount;
            public int morphMeshCount;
            public string modelPath;
            public string prefabPath;
            public string materialPath;
            public string albedoPath;
            public string emissionPath;
            public string limits = "Asset import and saved material binding; visible rendering and physics callbacks require play-mode checks.";
        }
    }
}
