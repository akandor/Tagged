using System.Windows.Media;

namespace TaggdWin.Themes
{
    /// <summary>
    /// The design tokens from the macOS/iOS app, mirrored for use in C# code
    /// (converters, dynamic brushes). The same colors are declared in Theme.xaml
    /// for use from XAML.
    /// </summary>
    public static class Palette
    {
        public static Color Hex(uint rgb, byte a = 0xFF) =>
            Color.FromArgb(a, (byte)((rgb >> 16) & 0xFF), (byte)((rgb >> 8) & 0xFF), (byte)(rgb & 0xFF));

        public static readonly Color Accent        = Hex(0xDEAA22);
        public static readonly Color Background     = Hex(0x0C0C0E);
        public static readonly Color Surface        = Hex(0x161618);
        public static readonly Color SurfaceRaised  = Hex(0x1E1E21);
        public static readonly Color Stroke         = Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF); // white 8%
        public static readonly Color TextPrimary    = Hex(0xF5F5F7);
        public static readonly Color TextSecondary  = Hex(0x9A9AA0);
        public static readonly Color TextTertiary   = Hex(0x5E5E63);
        public static readonly Color Danger         = Hex(0xE5484D);

        public static readonly Brush AccentBrush        = Frozen(Accent);
        public static readonly Brush TextPrimaryBrush   = Frozen(TextPrimary);
        public static readonly Brush TextTertiaryBrush  = Frozen(TextTertiary);
        public static readonly Brush AccentDimBrush     = Frozen(Color.FromArgb(0xA6, Accent.R, Accent.G, Accent.B)); // ~65%

        private static SolidColorBrush Frozen(Color c)
        {
            var b = new SolidColorBrush(c);
            b.Freeze();
            return b;
        }
    }
}
