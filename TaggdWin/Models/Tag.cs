using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace TaggdWin.Models
{
    /// <summary>A user tag. Mirrors the Swift <c>Tag</c> struct.</summary>
    public sealed class Tag : INotifyPropertyChanged
    {
        public Guid Id { get; set; } = Guid.NewGuid();

        private string _name = string.Empty;
        public string Name
        {
            get => _name;
            set
            {
                var trimmed = (value ?? string.Empty).Trim();
                if (_name == trimmed) return;
                _name = trimmed;
                OnPropertyChanged();
            }
        }

        public Tag() { }

        public Tag(string name)
        {
            _name = (name ?? string.Empty).Trim();
        }

        public event PropertyChangedEventHandler? PropertyChanged;

        private void OnPropertyChanged([CallerMemberName] string? p = null) =>
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(p));
    }
}
