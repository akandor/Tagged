using System;
using System.IO;
using System.Text.Json;

namespace TaggdWin.Services
{
    /// <summary>
    /// Small JSON-backed settings store in %APPDATA%\Tagged\settings.json.
    /// The macOS app uses UserDefaults for the same keys.
    /// </summary>
    public static class SettingsStore
    {
        private sealed class Model
        {
            public string ServerUrl { get; set; } = "";
            public string ApiToken { get; set; } = "";
            public bool ConfirmBeforeStop { get; set; } = false;
            public bool AutomaticallyChecksForUpdates { get; set; } = true;
        }

        public static string AppDataDir { get; } = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Tagged");

        private static readonly string FilePath = Path.Combine(AppDataDir, "settings.json");
        private static readonly Model Current = Load();

        private static Model Load()
        {
            try
            {
                if (File.Exists(FilePath))
                    return JsonSerializer.Deserialize<Model>(File.ReadAllText(FilePath)) ?? new Model();
            }
            catch { /* fall back to defaults */ }
            return new Model();
        }

        private static void Save()
        {
            try
            {
                Directory.CreateDirectory(AppDataDir);
                File.WriteAllText(FilePath,
                    JsonSerializer.Serialize(Current, new JsonSerializerOptions { WriteIndented = true }));
            }
            catch { /* best effort */ }
        }

        public static string ServerUrl
        {
            get => Current.ServerUrl;
            set { Current.ServerUrl = value ?? ""; Save(); }
        }

        public static string ApiToken
        {
            get => Current.ApiToken;
            set { Current.ApiToken = value ?? ""; Save(); }
        }

        public static bool ConfirmBeforeStop
        {
            get => Current.ConfirmBeforeStop;
            set { Current.ConfirmBeforeStop = value; Save(); }
        }

        public static bool AutomaticallyChecksForUpdates
        {
            get => Current.AutomaticallyChecksForUpdates;
            set { Current.AutomaticallyChecksForUpdates = value; Save(); }
        }
    }
}
