using System;
using System.Threading.Tasks;
using Velopack;
using Velopack.Sources;

namespace TaggdWin.Services
{
    /// <summary>
    /// Wraps Velopack, which delivers updates from GitHub Releases — the Windows
    /// analog of Sparkle on macOS. Updates only apply when the app is running
    /// from a Velopack install (not from `dotnet run` / the VS debugger).
    /// </summary>
    public static class UpdaterService
    {
        // The repo whose Releases host the packaged installers + delta packages.
        private const string RepoUrl = "https://github.com/akandor/Tagged";

        public enum Outcome { NotInstalled, UpToDate, Updated, Failed }

        public readonly struct Result
        {
            public Outcome Outcome { get; init; }
            public string Message { get; init; }
        }

        /// <summary>
        /// Must be the very first thing the process does. Handles Velopack's
        /// install/update/uninstall hook invocations and returns immediately in
        /// normal runs.
        /// </summary>
        public static void Bootstrap() => VelopackApp.Build().Run();

        private static UpdateManager CreateManager() =>
            new UpdateManager(new GithubSource(RepoUrl, null, prerelease: false));

        /// <summary>Silent background check used at launch (respects the user's toggle).</summary>
        public static async Task CheckInBackgroundAsync()
        {
            if (!SettingsStore.AutomaticallyChecksForUpdates) return;
            try
            {
                var mgr = CreateManager();
                if (!mgr.IsInstalled) return;
                var updates = await mgr.CheckForUpdatesAsync().ConfigureAwait(false);
                if (updates == null) return;
                await mgr.DownloadUpdatesAsync(updates).ConfigureAwait(false);
                // Staged; will be applied on next relaunch. (Silent — no restart.)
            }
            catch { /* ignore background failures */ }
        }

        /// <summary>User-initiated "Check for Updates…". Applies + restarts if found.</summary>
        public static async Task<Result> CheckAndApplyAsync()
        {
            try
            {
                var mgr = CreateManager();
                if (!mgr.IsInstalled)
                    return new Result { Outcome = Outcome.NotInstalled, Message = "Updates apply to installed builds only." };

                var updates = await mgr.CheckForUpdatesAsync().ConfigureAwait(false);
                if (updates == null)
                    return new Result { Outcome = Outcome.UpToDate, Message = "You're on the latest version." };

                await mgr.DownloadUpdatesAsync(updates).ConfigureAwait(false);
                // Applies the update and relaunches the app.
                mgr.ApplyUpdatesAndRestart(updates);
                return new Result { Outcome = Outcome.Updated, Message = "" };
            }
            catch (Exception ex)
            {
                return new Result { Outcome = Outcome.Failed, Message = ex.Message };
            }
        }
    }
}
