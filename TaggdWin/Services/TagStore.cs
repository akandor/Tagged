using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text.Json;
using TaggdWin.Models;

namespace TaggdWin.Services
{
    /// <summary>
    /// Persistent, ordered library of the user's tags, shared by the tray popup's
    /// picker and the settings tag manager. Backed by JSON in %APPDATA%\Tagged.
    /// Mirrors the Swift <c>TagStore</c>.
    /// </summary>
    public sealed class TagStore
    {
        public static TagStore Shared { get; } = new TagStore();

        private static readonly string FilePath = Path.Combine(SettingsStore.AppDataDir, "tags.json");

        public ObservableCollection<Tag> Tags { get; }

        private TagStore()
        {
            Tags = Load();
        }

        private static ObservableCollection<Tag> Load()
        {
            try
            {
                if (File.Exists(FilePath))
                {
                    var decoded = JsonSerializer.Deserialize<Tag[]>(File.ReadAllText(FilePath));
                    if (decoded != null)
                        return new ObservableCollection<Tag>(decoded.Where(t => !string.IsNullOrWhiteSpace(t.Name)));
                }
            }
            catch { /* fall back to empty */ }
            return new ObservableCollection<Tag>();
        }

        public void Save()
        {
            try
            {
                Directory.CreateDirectory(SettingsStore.AppDataDir);
                File.WriteAllText(FilePath,
                    JsonSerializer.Serialize(Tags.ToArray(), new JsonSerializerOptions { WriteIndented = true }));
            }
            catch { /* best effort */ }
        }

        /// <summary>Adds a tag (or returns the existing one for a duplicate name). Null for empty input.</summary>
        public Tag? Add(string name)
        {
            var trimmed = (name ?? "").Trim();
            if (trimmed.Length == 0) return null;
            var existing = Tags.FirstOrDefault(t => string.Equals(t.Name, trimmed, StringComparison.OrdinalIgnoreCase));
            if (existing != null) return existing;
            var tag = new Tag(trimmed);
            Tags.Add(tag);
            Save();
            return tag;
        }

        public void Rename(Guid id, string name)
        {
            var trimmed = (name ?? "").Trim();
            if (trimmed.Length == 0) return;
            var tag = Tags.FirstOrDefault(t => t.Id == id);
            if (tag == null || tag.Name == trimmed) return;
            tag.Name = trimmed;
            Save();
        }

        public void Remove(Tag tag)
        {
            if (Tags.Remove(tag)) Save();
        }

        public void Move(int from, int to)
        {
            if (from < 0 || from >= Tags.Count || to < 0 || to >= Tags.Count || from == to) return;
            Tags.Move(from, to);
            Save();
        }
    }
}
