using System;
using System.Collections.Specialized;
using System.Diagnostics;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using TaggdWin.Models;
using TaggdWin.Services;

namespace TaggdWin.Views
{
    public partial class SettingsWindow : Window
    {
        private bool _loading;
        private bool _syncingToken;

        public SettingsWindow()
        {
            InitializeComponent();
            LoadValues();

            TagsList.ItemsSource = TagStore.Shared.Tags;
            TagStore.Shared.Tags.CollectionChanged += OnTagsChanged;
            UpdateTagCount();

            Closed += (_, _) => TagStore.Shared.Tags.CollectionChanged -= OnTagsChanged;
            SourceInitialized += (_, _) => TryEnableDarkTitleBar();
        }

        private void LoadValues()
        {
            _loading = true;

            ServerUrlBox.Text = SettingsStore.ServerUrl;
            TokenPasswordBox.Password = SettingsStore.ApiToken;
            TokenTextBox.Text = SettingsStore.ApiToken;

            ConfirmToggle.IsChecked = SettingsStore.ConfirmBeforeStop;
            LaunchToggle.IsChecked = LaunchAtLogin.IsEnabled;
            AutoUpdateToggle.IsChecked = SettingsStore.AutomaticallyChecksForUpdates;

            var v = Assembly.GetExecutingAssembly().GetName().Version;
            VersionText.Text = v is null ? "1.0" : $"{v.Major}.{v.Minor}.{v.Build}";
            CopyrightText.Text = $"© {DateTime.Now.Year} Toepper.Rocks";

            _loading = false;
        }

        // ---- Server ----

        private void OnServerUrlChanged(object sender, TextChangedEventArgs e)
        {
            if (_loading) return;
            SettingsStore.ServerUrl = ServerUrlBox.Text;
            TestStatus.Text = "";
        }

        private void OnTokenPasswordChanged(object sender, RoutedEventArgs e)
        {
            if (_loading || _syncingToken) return;
            _syncingToken = true;
            TokenTextBox.Text = TokenPasswordBox.Password;
            _syncingToken = false;
            SettingsStore.ApiToken = TokenPasswordBox.Password;
            TestStatus.Text = "";
        }

        private void OnTokenTextChanged(object sender, TextChangedEventArgs e)
        {
            if (_loading || _syncingToken) return;
            _syncingToken = true;
            TokenPasswordBox.Password = TokenTextBox.Text;
            _syncingToken = false;
            SettingsStore.ApiToken = TokenTextBox.Text;
            TestStatus.Text = "";
        }

        private void OnToggleReveal(object sender, RoutedEventArgs e)
        {
            bool reveal = TokenTextBox.Visibility != Visibility.Visible;
            TokenTextBox.Visibility = reveal ? Visibility.Visible : Visibility.Collapsed;
            TokenPasswordBox.Visibility = reveal ? Visibility.Collapsed : Visibility.Visible;
            RevealGlyph.Text = reveal ? "\uE890" : "\uE7B3"; // View / RedEye
        }

        private async void OnTestConnection(object sender, RoutedEventArgs e)
        {
            var url = SettingsStore.ServerUrl.Trim();
            var token = SettingsStore.ApiToken.Trim();
            if (url.Length == 0 || token.Length == 0) return;

            TestStatus.Text = "Testing…";
            TestStatus.Foreground = (Brush)FindResource("TextSecondaryBrush");
            var result = await new TimeTaggerClient(url, token).TestConnectionAsync();
            TestStatus.Text = result.Kind switch
            {
                TimeTaggerClient.ResultKind.Success => "✓ Connected",
                TimeTaggerClient.ResultKind.Unauthorized => "✗ Invalid token",
                TimeTaggerClient.ResultKind.BadUrl => "✗ Invalid URL",
                _ => "✗ " + result.Message
            };
            TestStatus.Foreground = result.Kind == TimeTaggerClient.ResultKind.Success
                ? new SolidColorBrush(Color.FromRgb(0x3F, 0xB9, 0x50)) // green, matches the "Saved" toast
                : (Brush)FindResource("DangerBrush");
        }

        // ---- Timer ----

        private void OnConfirmChanged(object sender, RoutedEventArgs e)
        {
            if (_loading) return;
            SettingsStore.ConfirmBeforeStop = ConfirmToggle.IsChecked == true;
        }

        private void OnLaunchChanged(object sender, RoutedEventArgs e)
        {
            if (_loading) return;
            LaunchAtLogin.SetEnabled(LaunchToggle.IsChecked == true);
            _loading = true;
            LaunchToggle.IsChecked = LaunchAtLogin.IsEnabled;
            _loading = false;
        }

        // ---- Updates ----

        private void OnAutoUpdateChanged(object sender, RoutedEventArgs e)
        {
            if (_loading) return;
            SettingsStore.AutomaticallyChecksForUpdates = AutoUpdateToggle.IsChecked == true;
        }

        private async void OnCheckForUpdates(object sender, RoutedEventArgs e)
        {
            CheckUpdatesText.Text = "Checking…";
            var result = await UpdaterService.CheckAndApplyAsync();
            CheckUpdatesText.Text = "Check for Updates…";
            switch (result.Outcome)
            {
                case UpdaterService.Outcome.UpToDate:
                    MessageBox.Show(this, result.Message, "Tagged", MessageBoxButton.OK, MessageBoxImage.Information);
                    break;
                case UpdaterService.Outcome.NotInstalled:
                    MessageBox.Show(this, result.Message, "Tagged", MessageBoxButton.OK, MessageBoxImage.Information);
                    break;
                case UpdaterService.Outcome.Failed:
                    MessageBox.Show(this, "Update check failed:\n" + result.Message, "Tagged",
                        MessageBoxButton.OK, MessageBoxImage.Warning);
                    break;
                // Updated => the app restarts, nothing to show.
            }
        }

        // ---- Tags navigation ----

        private void OnManageTags(object sender, RoutedEventArgs e)
        {
            SettingsPanel.Visibility = Visibility.Collapsed;
            TagsPanel.Visibility = Visibility.Visible;
        }

        private void OnBackFromTags(object sender, RoutedEventArgs e)
        {
            TagsPanel.Visibility = Visibility.Collapsed;
            SettingsPanel.Visibility = Visibility.Visible;
            UpdateTagCount();
        }

        // ---- Tag management ----

        private void OnAddNewTag(object sender, RoutedEventArgs e) => AddNewTag();

        private void OnNewTagKeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter) { AddNewTag(); e.Handled = true; }
        }

        private void AddNewTag()
        {
            var name = NewTagBox.Text.Trim();
            if (name.Length == 0) return;
            TagStore.Shared.Add(name);
            NewTagBox.Clear();
            NewTagBox.Focus();
        }

        private void OnTagRenamed(object sender, RoutedEventArgs e)
        {
            if (sender is not TextBox tb || tb.DataContext is not Tag tag) return;
            var name = tb.Text.Trim();
            if (name.Length == 0) { tb.Text = tag.Name; return; }
            TagStore.Shared.Rename(tag.Id, name);
        }

        private void OnMoveTagUp(object sender, RoutedEventArgs e) => MoveTag(sender, -1);
        private void OnMoveTagDown(object sender, RoutedEventArgs e) => MoveTag(sender, +1);

        private void MoveTag(object sender, int delta)
        {
            if (sender is not FrameworkElement fe || fe.DataContext is not Tag tag) return;
            int index = TagStore.Shared.Tags.IndexOf(tag);
            TagStore.Shared.Move(index, index + delta);
        }

        private void OnDeleteTag(object sender, RoutedEventArgs e)
        {
            if (sender is FrameworkElement fe && fe.DataContext is Tag tag)
                TagStore.Shared.Remove(tag);
        }

        private void OnTagsChanged(object? sender, NotifyCollectionChangedEventArgs e) => UpdateTagCount();

        private void UpdateTagCount() => TagsCountText.Text = TagStore.Shared.Tags.Count.ToString();

        // ---- Links / quit ----

        private void OnOpenGitHub(object sender, RoutedEventArgs e) => OpenUrl("https://github.com/akandor/Tagged");
        private void OnBuyCoffee(object sender, RoutedEventArgs e) => OpenUrl("https://buymeacoffee.com/toepper.rocks");
        private void OnQuit(object sender, RoutedEventArgs e) => ((App)Application.Current).QuitApp();

        private static void OpenUrl(string url)
        {
            try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
            catch { /* ignore */ }
        }

        // ---- Dark title bar ----

        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        private void TryEnableDarkTitleBar()
        {
            try
            {
                var hwnd = new WindowInteropHelper(this).Handle;
                int useDark = 1;
                // DWMWA_USE_IMMERSIVE_DARK_MODE = 20
                DwmSetWindowAttribute(hwnd, 20, ref useDark, sizeof(int));
            }
            catch { /* not fatal */ }
        }
    }
}
