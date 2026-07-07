using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using TaggdWin.Models;
using TaggdWin.Themes;

namespace TaggdWin.Services
{
    /// <summary>
    /// Observable stopwatch driving the tray popup. The app owns the running
    /// clock; nothing reaches the server until a session is stopped. Faithful
    /// port of the Swift <c>TimeTracker</c>.
    /// </summary>
    public sealed class TimeTracker : INotifyPropertyChanged
    {
        public enum Phase { Idle, Running, Paused }

        public enum SyncStatusKind { Disabled, Syncing, Synced, Failed }

        // ---- Observable state ----

        private Phase _phase = Phase.Idle;
        public Phase CurrentPhase
        {
            get => _phase;
            private set
            {
                if (_phase == value) return;
                _phase = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(IsIdle));
                OnPropertyChanged(nameof(IsRunning));
                OnPropertyChanged(nameof(IsPaused));
                OnPropertyChanged(nameof(TimerBrush));
                OnPropertyChanged(nameof(TimerUnitBrush));
            }
        }

        public bool IsIdle => _phase == Phase.Idle;
        public bool IsRunning => _phase == Phase.Running;
        public bool IsPaused => _phase == Phase.Paused;

        private string _taskDescription = "";
        public string TaskDescription
        {
            get => _taskDescription;
            set { if (_taskDescription != value) { _taskDescription = value ?? ""; OnPropertyChanged(); } }
        }

        public ObservableCollection<Tag> SelectedTags { get; } = new();

        private TimeSpan _elapsed = TimeSpan.Zero;
        public TimeSpan Elapsed
        {
            get => _elapsed;
            private set
            {
                if (_elapsed == value) return;
                _elapsed = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(HH));
                OnPropertyChanged(nameof(MM));
                OnPropertyChanged(nameof(SS));
            }
        }

        public string HH => ((int)_elapsed.TotalHours).ToString("00");
        public string MM => _elapsed.Minutes.ToString("00");
        public string SS => _elapsed.Seconds.ToString("00");

        public Brush TimerBrush => IsRunning ? Palette.AccentBrush : Palette.TextPrimaryBrush;
        public Brush TimerUnitBrush => IsRunning ? Palette.AccentDimBrush : Palette.TextTertiaryBrush;

        /// <summary>Raised on the UI thread whenever a sync finishes or fails.</summary>
        public event Action<SyncStatusKind, string>? SyncStatusChanged;

        // ---- Internals ----

        private TimeSpan _accumulated = TimeSpan.Zero;
        private DateTime? _startDate;
        private readonly DispatcherTimer _timer;

        private readonly List<(long start, long end)> _segments = new();
        private long _currentSegmentStart;
        private readonly List<TimeTaggerClient.Record> _pendingRecords = new();

        public TimeTracker()
        {
            _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
            _timer.Tick += (_, _) => Elapsed = _accumulated + IntervalSinceStart();
        }

        private static long Now() => DateTimeOffset.UtcNow.ToUnixTimeSeconds();

        // ---- Controls ----

        public void Start()
        {
            if (IsRunning) return;
            _startDate = DateTime.UtcNow;
            _currentSegmentStart = Now();
            _segments.Clear();
            CurrentPhase = Phase.Running;
            StartTicking();
        }

        public void Pause()
        {
            if (!IsRunning) return;
            _accumulated += IntervalSinceStart();
            CloseCurrentSegment();
            _startDate = null;
            Elapsed = _accumulated;
            CurrentPhase = Phase.Paused;
            _timer.Stop();
        }

        public void Resume()
        {
            if (!IsPaused) return;
            _startDate = DateTime.UtcNow;
            _currentSegmentStart = Now();
            CurrentPhase = Phase.Running;
            StartTicking();
        }

        public void Stop()
        {
            if (IsRunning) CloseCurrentSegment();
            EnqueueSessionRecords();

            _timer.Stop();
            _accumulated = TimeSpan.Zero;
            _startDate = null;
            Elapsed = TimeSpan.Zero;
            _segments.Clear();
            CurrentPhase = Phase.Idle;

            Flush();
        }

        // ---- Tags ----

        public void AddTag(Tag tag)
        {
            if (SelectedTags.Any(t => string.Equals(t.Name, tag.Name, StringComparison.OrdinalIgnoreCase))) return;
            SelectedTags.Add(tag);
        }

        public void RemoveTag(Tag tag)
        {
            var match = SelectedTags.FirstOrDefault(t => t.Id == tag.Id);
            if (match != null) SelectedTags.Remove(match);
        }

        // ---- Ticking ----

        private TimeSpan IntervalSinceStart() =>
            _startDate.HasValue ? DateTime.UtcNow - _startDate.Value : TimeSpan.Zero;

        private void StartTicking()
        {
            Elapsed = _accumulated + IntervalSinceStart();
            _timer.Start();
        }

        private void CloseCurrentSegment()
        {
            long now = Now();
            _segments.Add((_currentSegmentStart, Math.Max(now, _currentSegmentStart + 1)));
        }

        // ---- Server sync ----

        private TimeTaggerClient? MakeClient()
        {
            var url = (SettingsStore.ServerUrl ?? "").Trim();
            var token = (SettingsStore.ApiToken ?? "").Trim();
            if (url.Length == 0 || token.Length == 0) return null;
            return new TimeTaggerClient(url, token);
        }

        private string RecordDescription()
        {
            var parts = new List<string>();
            var text = TaskDescription.Trim();
            if (text.Length > 0) parts.Add(text);
            foreach (var tag in SelectedTags)
            {
                var cleaned = string.Join("-",
                    tag.Name.Split(default(char[]?), StringSplitOptions.RemoveEmptyEntries)
                            .SelectMany(s => s.Split('#', StringSplitOptions.RemoveEmptyEntries)));
                if (cleaned.Length > 0) parts.Add("#" + cleaned);
            }
            return string.Join(" ", parts);
        }

        private void EnqueueSessionRecords()
        {
            if (MakeClient() == null || _segments.Count == 0) return;
            var ds = RecordDescription();
            long mt = Now();
            foreach (var seg in _segments)
            {
                _pendingRecords.Add(new TimeTaggerClient.Record
                {
                    Key = TimeTaggerClient.GenerateKey(),
                    T1 = seg.start,
                    T2 = seg.end,
                    Mt = mt,
                    Ds = ds
                });
            }
        }

        private void Flush()
        {
            if (_pendingRecords.Count == 0) return;
            var client = MakeClient();
            if (client == null)
            {
                RaiseSync(SyncStatusKind.Disabled, "");
                return;
            }

            var batch = _pendingRecords.ToList();
            var keys = batch.Select(r => r.Key).ToHashSet();
            RaiseSync(SyncStatusKind.Syncing, "");

            _ = Task.Run(async () =>
            {
                var result = await client.PushRecordsAsync(batch).ConfigureAwait(false);
                Dispatch(() =>
                {
                    switch (result.Kind)
                    {
                        case TimeTaggerClient.ResultKind.Success:
                            _pendingRecords.RemoveAll(r => keys.Contains(r.Key));
                            RaiseSync(SyncStatusKind.Synced, "");
                            break;
                        case TimeTaggerClient.ResultKind.Unauthorized:
                            RaiseSync(SyncStatusKind.Failed, "Invalid token");
                            break;
                        case TimeTaggerClient.ResultKind.Rejected:
                            RaiseSync(SyncStatusKind.Failed, result.Message);
                            break;
                        case TimeTaggerClient.ResultKind.BadUrl:
                            RaiseSync(SyncStatusKind.Failed, "Invalid server URL");
                            break;
                        default:
                            RaiseSync(SyncStatusKind.Failed, result.Message);
                            break;
                    }
                });
            });
        }

        public void RetrySync() => Flush();

        private void RaiseSync(SyncStatusKind kind, string message) => SyncStatusChanged?.Invoke(kind, message);

        private static void Dispatch(Action action)
        {
            var app = Application.Current;
            if (app?.Dispatcher != null && !app.Dispatcher.CheckAccess())
                app.Dispatcher.Invoke(action);
            else
                action();
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnPropertyChanged([CallerMemberName] string? p = null) =>
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(p));
    }
}
