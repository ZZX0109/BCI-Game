using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using FirstPersonSokoban.Core;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace FirstPersonSokoban.Editor
{
    /// <summary>Local, reproducible Windows build entry. Unity tests are run by Tools/run_delivery.py.</summary>
    public static class DeliveryBuild
    {
        private const string ScenePath = "Assets/FirstPersonSokoban/Scenes/PuzzleScene.unity";

        [Serializable]
        private sealed class ValidationSummary
        {
            public string status;
            public string unityVersion;
            public string sourceCommit;
            public string sourceFingerprint;
        }

        [Serializable]
        private sealed class FileHash
        {
            public string path;
            public string sha256;
            public long bytes;
        }

        [Serializable]
        private sealed class BuildManifest
        {
            public int schemaVersion = 1;
            public string builtAtUtc;
            public string unityVersion;
            public string target = "StandaloneWindows64";
            public string sourceCommit;
            public string sourceFingerprint;
            public string unityTests;
            public string guiAcceptance = "not_run";
            public int levelCount;
            public int[] minimumPushes;
            public FileHash[] files;
        }

        [MenuItem("First Person Sokoban/Delivery/Validate Levels and Build Windows")]
        public static void BuildWindows()
        {
            string root = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
            string output = Argument("-buildOutput");
            if (string.IsNullOrEmpty(output))
                output = Path.Combine(root, "BuildOutput", "Windows-" + DateTime.UtcNow.ToString("yyyyMMddTHHmmssfff"));
            output = Path.GetFullPath(output);
            string allowed = Path.GetFullPath(Path.Combine(root, "BuildOutput")) + Path.DirectorySeparatorChar;
            if (!output.StartsWith(allowed, StringComparison.OrdinalIgnoreCase))
                throw new BuildFailedException("Delivery output must be a new directory inside BuildOutput.");
            if (Directory.Exists(output) && Directory.EnumerateFileSystemEntries(output).Any())
                throw new BuildFailedException("Output directory is not empty. Use a fresh delivery directory.");

            int[] pushes = ValidateLevels();
            if (AssetDatabase.LoadAssetAtPath<SceneAsset>(ScenePath) == null)
                throw new BuildFailedException("PuzzleScene is missing. Restore assets before building.");
            if (!BuildPipeline.IsBuildTargetSupported(BuildTargetGroup.Standalone, BuildTarget.StandaloneWindows64))
                throw new BuildFailedException("Install Windows Build Support for this exact Unity Editor version.");

            string fingerprint = SourceFingerprint(root);
            string evidence = Argument("-validationDirectory");
            ValidationSummary validation = null;
            if (!string.IsNullOrEmpty(evidence))
            {
                string summaryPath = Path.Combine(evidence, "validation-summary.json");
                if (!File.Exists(summaryPath)) throw new BuildFailedException("Validation summary is missing.");
                validation = JsonUtility.FromJson<ValidationSummary>(File.ReadAllText(summaryPath));
                if (validation == null || validation.status != "passed" ||
                    validation.unityVersion != Application.unityVersion || validation.sourceFingerprint != fingerprint)
                    throw new BuildFailedException("Validation evidence does not match this source tree and Editor.");
                foreach (string mode in new[] { "EditMode", "PlayMode" })
                    if (!File.Exists(Path.Combine(evidence, mode + "-results.xml")))
                        throw new BuildFailedException(mode + " XML evidence is missing.");
            }

            Directory.CreateDirectory(output);
            BuildReport report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = new[] { ScenePath },
                locationPathName = Path.Combine(output, "FirstPersonSokoban.exe"),
                target = BuildTarget.StandaloneWindows64,
                options = BuildOptions.None
            });
            if (report.summary.result != BuildResult.Succeeded)
                throw new BuildFailedException("Windows player build failed: " + report.summary.result);
            if (!File.Exists(Path.Combine(output, "UnityPlayer.dll")) ||
                !Directory.Exists(Path.Combine(output, "FirstPersonSokoban_Data")))
                throw new BuildFailedException("Windows runtime output is incomplete.");

            string fontLicense = Path.Combine(root, "Assets/FirstPersonSokoban/Resources/Fonts/LICENSE.txt");
            if (File.Exists(fontLicense))
            {
                string notices = Path.Combine(output, "ThirdPartyNotices");
                Directory.CreateDirectory(notices);
                File.Copy(fontLicense, Path.Combine(notices, "SokobanUISans-LICENSE.txt"));
            }

            if (validation != null)
            {
                string evidenceTarget = Path.Combine(output, "Validation");
                Directory.CreateDirectory(evidenceTarget);
                foreach (string file in Directory.GetFiles(evidence))
                    File.Copy(file, Path.Combine(evidenceTarget, Path.GetFileName(file)), true);
            }
            string sourceCommit = validation?.sourceCommit ?? Argument("-sourceCommit") ?? "unknown";
            var manifest = new BuildManifest
            {
                builtAtUtc = DateTime.UtcNow.ToString("o"),
                unityVersion = Application.unityVersion,
                sourceCommit = sourceCommit,
                sourceFingerprint = fingerprint,
                unityTests = validation == null ? "not_run" : "passed",
                levelCount = pushes.Length,
                minimumPushes = pushes,
                files = Directory.GetFiles(output, "*", SearchOption.AllDirectories)
                    .OrderBy(file => file, StringComparer.Ordinal)
                    .Select(file => new FileHash
                    {
                        path = Relative(output, file),
                        bytes = new FileInfo(file).Length,
                        sha256 = HashFile(file)
                    }).ToArray()
            };
            File.WriteAllText(Path.Combine(output, "build-manifest.json"), JsonUtility.ToJson(manifest, true), new UTF8Encoding(false));
            Debug.Log("Windows delivery built: " + output + "; Unity tests: " + manifest.unityTests + "; GUI: not_run");
        }

        public static int[] ValidateLevels()
        {
            var pushes = new List<int>();
            foreach (LevelEntry entry in LevelCatalog.Entries)
            {
                TextAsset map = Resources.Load<TextAsset>("Levels/" + entry.Resource);
                if (map == null) throw new BuildFailedException("Missing level: " + entry.Resource);
                LevelDefinition level = LevelValidator.ParseAndValidate(map.text, entry.Title, entry.InitialYaw);
                SolveResult result = LevelSolver.Solve(level, 100000);
                if (result.Status != SolveStatus.Solved)
                    throw new BuildFailedException(entry.Resource + " validation failed: " + result.Status);
                pushes.Add(result.MinimumPushes);
            }
            return pushes.ToArray();
        }

        private static string Argument(string key)
        {
            string[] args = Environment.GetCommandLineArgs();
            int index = Array.IndexOf(args, key);
            return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
        }

        private static string SourceFingerprint(string root)
        {
            var files = new List<string>();
            foreach (string name in new[] { "Assets", "Packages", "ProjectSettings" })
                files.AddRange(Directory.GetFiles(Path.Combine(root, name), "*", SearchOption.AllDirectories));
            string content = string.Concat(files.OrderBy(file => Relative(root, file), StringComparer.Ordinal)
                .Select(file => Relative(root, file) + "\t" + HashFile(file) + "\n"));
            using (SHA256 sha = SHA256.Create())
                return Hex(sha.ComputeHash(Encoding.UTF8.GetBytes(content)));
        }

        private static string Relative(string root, string file)
            => file.Substring(root.TrimEnd(Path.DirectorySeparatorChar).Length + 1).Replace('\\', '/');

        private static string HashFile(string file)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = File.OpenRead(file)) return Hex(sha.ComputeHash(stream));
        }

        private static string Hex(byte[] bytes) => BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant();
    }
}
