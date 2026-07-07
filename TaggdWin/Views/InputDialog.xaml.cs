using System.Windows;

namespace TaggdWin.Views
{
    /// <summary>Minimal themed text-input dialog (used for "New Tag…").</summary>
    public partial class InputDialog : Window
    {
        public string Value => ValueBox.Text;

        public InputDialog(string title, string message)
        {
            InitializeComponent();
            TitleText.Text = title;
            MessageText.Text = message;
            Loaded += (_, _) => { ValueBox.Focus(); };
        }

        private void OnOk(object sender, RoutedEventArgs e) { DialogResult = true; Close(); }
        private void OnCancel(object sender, RoutedEventArgs e) { DialogResult = false; Close(); }

        public static string? Prompt(Window owner, string title, string message)
        {
            var dialog = new InputDialog(title, message) { Owner = owner };
            return dialog.ShowDialog() == true ? dialog.Value : null;
        }
    }
}
