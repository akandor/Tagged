using System;
using Microsoft.Win32;

namespace TaggdWin.Services
{
    /// <summary>
    /// "Launch at Login" via the per-user Run registry key — the Windows analog
    /// of the macOS SMAppService login item. No admin rights required.
    /// </summary>
    public static class LaunchAtLogin
    {
        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string ValueName = "Tagged";

        private static string ExePath => Environment.ProcessPath ?? "";

        public static bool IsEnabled
        {
            get
            {
                try
                {
                    using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: false);
                    return key?.GetValue(ValueName) is string;
                }
                catch { return false; }
            }
        }

        public static void SetEnabled(bool enabled)
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true)
                                ?? Registry.CurrentUser.CreateSubKey(RunKey);
                if (key == null) return;

                if (enabled)
                    key.SetValue(ValueName, $"\"{ExePath}\"");
                else if (key.GetValue(ValueName) != null)
                    key.DeleteValue(ValueName, throwOnMissingValue: false);
            }
            catch { /* best effort */ }
        }
    }
}
