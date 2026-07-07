using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace TaggdWin.Converters
{
    /// <summary>Count &gt; 0 =&gt; Visible. Pass parameter "empty" to invert (Visible when count == 0).</summary>
    public sealed class CountToVisibilityConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            int count = value is int i ? i : 0;
            bool whenEmpty = string.Equals(parameter as string, "empty", StringComparison.OrdinalIgnoreCase);
            bool visible = whenEmpty ? count == 0 : count > 0;
            return visible ? Visibility.Visible : Visibility.Collapsed;
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
            => throw new NotSupportedException();
    }

    /// <summary>Empty/whitespace string =&gt; Visible (used for text-box placeholders).</summary>
    public sealed class StringEmptyToVisibilityConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
            => string.IsNullOrEmpty(value as string) ? Visibility.Visible : Visibility.Collapsed;

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
            => throw new NotSupportedException();
    }
}
