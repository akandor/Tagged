using System;
using System.Windows;
using WinForms = System.Windows.Forms;
using Drawing = System.Drawing;
using TaggdWin.Services;
using TaggdWin.Views;

namespace TaggdWin
{
    /// <summary>
    /// Application entry point. Runs as a tray (notification-area) app with no
    /// main window — the Windows equivalent of the macOS status-bar app.
    /// </summary>
    public partial class App : Application
    {
        /// <summary>The single shared stopwatch, used by the popup and settings.</summary>
        public static TimeTracker Tracker { get; } = new TimeTracker();

        private WinForms.NotifyIcon? _notifyIcon;
        private TrayPopup? _popup;
        private SettingsWindow? _settings;

        protected override void OnStartup(StartupEventArgs e)
        {
            // Velopack must run before any other app logic.
            UpdaterService.Bootstrap();

            base.OnStartup(e);

            SetupTrayIcon();

            // Silent background update check (respects the user's toggle).
            _ = UpdaterService.CheckInBackgroundAsync();
        }

        private void SetupTrayIcon()
        {
            _notifyIcon = new WinForms.NotifyIcon
            {
                Text = "Tagged",
                Visible = true,
                Icon = LoadTrayIcon()
            };

            var menu = new WinForms.ContextMenuStrip();
            menu.Items.Add("Settings…", null, (_, _) => ShowSettings());
            menu.Items.Add(new WinForms.ToolStripSeparator());
            menu.Items.Add("Quit Tagged", null, (_, _) => QuitApp());
            _notifyIcon.ContextMenuStrip = menu;

            _notifyIcon.MouseClick += (_, args) =>
            {
                if (args.Button == WinForms.MouseButtons.Left)
                    TogglePopup();
            };
        }

        private Drawing.Icon LoadTrayIcon()
        {
            var info = GetResourceStream(new Uri("pack://application:,,,/Assets/tray.ico"));
            using var stream = info!.Stream;
            return new Drawing.Icon(stream);
        }

        // ---- Popup ----

        private void TogglePopup()
        {
            _popup ??= new TrayPopup();
            if (_popup.IsVisible)
                _popup.Hide();
            else
                _popup.ShowNearTray();
        }

        // ---- Settings ----

        public void ShowSettings()
        {
            _popup?.Hide();

            if (_settings == null)
            {
                _settings = new SettingsWindow();
                _settings.Closed += (_, _) => _settings = null;
            }
            _settings.Show();
            _settings.Activate();
        }

        // ---- Quit ----

        public void QuitApp()
        {
            if (_notifyIcon != null)
            {
                _notifyIcon.Visible = false;
                _notifyIcon.Dispose();
                _notifyIcon = null;
            }
            Shutdown();
        }
    }
}
