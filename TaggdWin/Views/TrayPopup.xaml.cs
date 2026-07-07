using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using TaggdWin.Models;
using TaggdWin.Services;

namespace TaggdWin.Views
{
    public partial class TrayPopup : Window
    {
        private TimeTracker Tracker => App.Tracker;
        private readonly DispatcherTimer _toastTimer = new();
        private bool _suppressHide;

        public TrayPopup()
        {
            InitializeComponent();
            DataContext = Tracker;

            Tracker.SyncStatusChanged += OnSyncStatusChanged;
            _toastTimer.Tick += (_, _) => { _toastTimer.Stop(); Toast.Visibility = Visibility.Collapsed; };
            Deactivated += (_, _) => { if (!_suppressHide) Hide(); };
        }

        /// <summary>Positions the popup at the bottom-right of the work area (near the tray) and shows it.</summary>
        public void ShowNearTray()
        {
            Show();
            var wa = SystemParameters.WorkArea;
            Left = wa.Right - Width - 4;
            Top = wa.Bottom - ActualHeight - 4;
            Activate();
            DescriptionBox.Focus();
        }

        // ---- Header ----

        private void OnOpenSettings(object sender, RoutedEventArgs e) => ((App)Application.Current).ShowSettings();

        private void OnQuit(object sender, RoutedEventArgs e) => ((App)Application.Current).QuitApp();

        // ---- Controls ----

        private void OnStart(object sender, RoutedEventArgs e) => Tracker.Start();
        private void OnPause(object sender, RoutedEventArgs e) => Tracker.Pause();
        private void OnResume(object sender, RoutedEventArgs e) => Tracker.Resume();

        private void OnStop(object sender, RoutedEventArgs e)
        {
            if (SettingsStore.ConfirmBeforeStop)
            {
                _suppressHide = true;
                var result = MessageBox.Show(this,
                    "The current time will be saved and the timer reset.",
                    "Stop this session?", MessageBoxButton.YesNo, MessageBoxImage.Question);
                _suppressHide = false;
                if (result != MessageBoxResult.Yes) return;
            }
            Tracker.Stop();
        }

        // ---- Tags ----

        private void OnAddTag(object sender, RoutedEventArgs e)
        {
            var taken = Tracker.SelectedTags.Select(t => t.Name.ToLowerInvariant()).ToHashSet();
            var available = TagStore.Shared.Tags.Where(t => !taken.Contains(t.Name.ToLowerInvariant())).ToList();

            var menu = new ContextMenu();
            foreach (var tag in available)
            {
                var item = new MenuItem { Header = tag.Name, Tag = tag };
                item.Click += (_, _) => Tracker.AddTag(tag);
                menu.Items.Add(item);
            }
            if (available.Count > 0) menu.Items.Add(new Separator());

            var newItem = new MenuItem { Header = "New Tag…" };
            newItem.Click += (_, _) => CreateNewTag();
            menu.Items.Add(newItem);

            menu.PlacementTarget = (UIElement)sender;
            menu.IsOpen = true;
        }

        private void CreateNewTag()
        {
            _suppressHide = true;
            var name = InputDialog.Prompt(this, "New Tag", "Create a custom tag for this session.");
            _suppressHide = false;
            Activate();

            var trimmed = (name ?? "").Trim();
            if (trimmed.Length == 0) return;
            var tag = TagStore.Shared.Add(trimmed);
            if (tag != null) Tracker.AddTag(tag);
        }

        private void OnRemoveTag(object sender, RoutedEventArgs e)
        {
            if (sender is FrameworkElement fe && fe.DataContext is Tag tag)
                Tracker.RemoveTag(tag);
        }

        // ---- Toast ----

        private void OnSyncStatusChanged(TimeTracker.SyncStatusKind kind, string message)
        {
            switch (kind)
            {
                case TimeTracker.SyncStatusKind.Synced:
                    ShowToast(saved: true);
                    break;
                case TimeTracker.SyncStatusKind.Failed:
                    ShowToast(saved: false);
                    break;
            }
        }

        private void ShowToast(bool saved)
        {
            ToastGlyph.Text = saved ? "\uE930" : "\uE7BA"; // Completed / Warning
            ToastGlyph.Foreground = saved
                ? new SolidColorBrush(Color.FromRgb(0x3F, 0xB9, 0x50))
                : (Brush)FindResource("DangerBrush");
            ToastText.Text = saved ? "Saved" : "Not saved";
            ToastRetry.Visibility = saved ? Visibility.Collapsed : Visibility.Visible;

            Toast.Visibility = Visibility.Visible;
            _toastTimer.Stop();
            _toastTimer.Interval = TimeSpan.FromSeconds(saved ? 2.5 : 5);
            _toastTimer.Start();
        }

        private void OnRetry(object sender, RoutedEventArgs e) => Tracker.RetrySync();
    }
}
