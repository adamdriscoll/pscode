using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using AvaloniaEdit.TextMate;
using AvaloniaEdit;
using AvaloniaEdit.CodeCompletion;
using AvaloniaEdit.Document;
using AvaloniaEdit.Editing;
using AvaloniaEdit.Folding;
using AvaloniaEdit.Rendering;
using TextMateSharp.Grammars;
using System.Management.Automation.Runspaces;
using System.Management.Automation;
using System.Collections;
using System.Linq;
using ICSharpCode.AvalonEdit.AddIn;
using System.Collections.ObjectModel;
using System.Management.Automation.Language;

namespace PSCode
{
    using Pair = KeyValuePair<int, IControl>;

    public class MainWindow : Window
    {
        private readonly TextEditor _textEditor;
        private readonly TextMate.Installation _textMateInstallation;
        private CompletionWindow _completionWindow;
        private OverloadInsightWindow _insightWindow;
        private ElementGenerator _generator = new ElementGenerator();
        private RegistryOptions _registryOptions;
        private int _currentTheme = (int)ThemeName.DarkPlus;
        // RUNSPACE
        private Runspace _runspace;
        private TextMarkerService textMarkerService;

        public MainWindow()
        {
            InitializeComponent();

            // RUNSPACE
            _runspace = RunspaceFactory.CreateRunspace();
            _runspace.Open();

            var btnRun = this.FindControl<Button>("btnRun");
            btnRun.Click += BtnRun_Click;

            _textEditor = this.FindControl<TextEditor>("Editor");
            _textEditor.Background = Brushes.Transparent;
            _textEditor.ShowLineNumbers = true;
            _textEditor.ContextMenu = new ContextMenu
            {
                Items = new List<MenuItem>
                {
                    new MenuItem { Header = "Copy", InputGesture = new KeyGesture(Key.C, KeyModifiers.Control) },
                    new MenuItem { Header = "Paste", InputGesture = new KeyGesture(Key.V, KeyModifiers.Control) },
                    new MenuItem { Header = "Cut", InputGesture = new KeyGesture(Key.X, KeyModifiers.Control) }
                }
            };
            _textEditor.TextArea.Background = this.Background;
            _textEditor.TextArea.TextEntered += textEditor_TextArea_TextEntered;
            _textEditor.TextArea.TextEntering += textEditor_TextArea_TextEntering;
            _textEditor.Options.ShowBoxForControlCharacters = true;
            _textEditor.TextArea.IndentationStrategy = new AvaloniaEdit.Indentation.CSharp.CSharpIndentationStrategy(_textEditor.Options);
            _textEditor.TextArea.RightClickMovesCaret = true;

            _textEditor.TextArea.TextView.ElementGenerators.Add(_generator);

            _registryOptions = new RegistryOptions(
                (ThemeName)_currentTheme);

            _textMateInstallation = _textEditor.InstallTextMate(_registryOptions);

            Language language = _registryOptions.GetLanguageByExtension(".ps1"); // LANGUAGE

            string scopeName = _registryOptions.GetScopeByLanguageId(language.Id);

            var document = new TextDocument("# Welcome to PSCode" + Environment.NewLine); // DOCUMENT
            _textEditor.Document = document;
            _textMateInstallation.SetGrammar(_registryOptions.GetScopeByLanguageId(language.Id));

            textMarkerService = new TextMarkerService(document);
            _textEditor.TextArea.TextView.BackgroundRenderers.Add(textMarkerService);
            _textEditor.TextArea.TextView.LineTransformers.Add(textMarkerService);

            this.AddHandler(PointerWheelChangedEvent, (o, i) =>
            {
                if (i.KeyModifiers != KeyModifiers.Control) return;
                if (i.Delta.Y > 0) _textEditor.FontSize++;
                else _textEditor.FontSize = _textEditor.FontSize > 1 ? _textEditor.FontSize - 1 : 1;
            }, RoutingStrategies.Bubble, true);
        }

        private void BtnRun_Click(object sender, RoutedEventArgs e)
        {
            // RUN
            using (var ps = PowerShell.Create())
            {
                ps.Runspace = _runspace;
                ps.AddScript(_textEditor.Text);

                try
                {
                    ps.Invoke();

                    if (ps.HadErrors)
                    {
                        foreach (var error in ps.Streams.Error)
                        {
                            var messageBoxStandardWindow = MessageBox.Avalonia.MessageBoxManager.GetMessageBoxStandardWindow("Error", error.ToString());
                            messageBoxStandardWindow.Show();
                        }
                    }
                }
                catch (Exception ex)
                {
                    var messageBoxStandardWindow = MessageBox.Avalonia.MessageBoxManager.GetMessageBoxStandardWindow("Error", ex.Message);
                    messageBoxStandardWindow.Show();
                }

            }
        }

        protected override void OnClosed(EventArgs e)
        {
            base.OnClosed(e);

            _textMateInstallation.Dispose();
        }

        private void InitializeComponent()
        {
            AvaloniaXamlLoader.Load(this);
        }

        private void textEditor_TextArea_TextEntering(object sender, TextInputEventArgs e)
        {
            if (e.Text.Length > 0 && _completionWindow != null)
            {
                if (!char.IsLetterOrDigit(e.Text[0]))
                {
                    // Whenever a non-letter is typed while the completion window is open,
                    // insert the currently selected element.
                    _completionWindow.CompletionList.RequestInsertion(e);
                }
            }

            _insightWindow?.Hide();

            // Do not set e.Handled=true.
            // We still want to insert the character that was typed.
        }

        private void textEditor_TextArea_TextEntered(object sender, TextInputEventArgs e)
        {
            // ENTERED

            Parser.ParseInput(_textEditor.Text, out Token[] tokens, out ParseError[] errors);

            textMarkerService.RemoveAll(x => true);

            foreach (var error in errors)
            {
                var marker = textMarkerService.Create(error.Extent.StartOffset, error.Extent.EndOffset - error.Extent.StartOffset);
                marker.ToolTip = error.Message;
                marker.Tag = error.Message;
                marker.MarkerTypes = TextMarkerTypes.NormalUnderline;
                marker.MarkerColor = Color.FromRgb(255, 0, 0);
            }

            if (e.Text == "-" || e.Text == "$" || e.Text == "." || e.Text == ":")
            {
                _completionWindow = new CompletionWindow(_textEditor.TextArea);
                _completionWindow.Closed += (o, args) => _completionWindow = null;

                Runspace.DefaultRunspace = _runspace;
                var completion = CommandCompletion.CompleteInput(_textEditor.Text, _textEditor.CaretOffset, new Hashtable());

                var data = _completionWindow.CompletionList.CompletionData;
                foreach (var item in completion.CompletionMatches)
                {
                    var insertText = item.CompletionText;
                    if (e.Text == "-")
                    {
                        insertText = insertText.Split('-').Last();
                    }
                    data.Add(new CompletionData(item.ListItemText, insertText));
                }

                _completionWindow.Show();
            }
            else if (e.Text == "(")
            {
                _insightWindow = new OverloadInsightWindow(_textEditor.TextArea);
                _insightWindow.Closed += (o, args) => _insightWindow = null;

                _insightWindow.Provider = new MyOverloadProvider(new[]
                {
                    ("Method1(int, string)", "Method1 description"),
                    ("Method2(int)", "Method2 description"),
                    ("Method3(string)", "Method3 description"),
                });

                _insightWindow.Show();
            }
        }

        private class MyOverloadProvider : IOverloadProvider
        {
            private readonly IList<(string header, string content)> _items;
            private int _selectedIndex;

            public MyOverloadProvider(IList<(string header, string content)> items)
            {
                _items = items;
                SelectedIndex = 0;
            }

            public int SelectedIndex
            {
                get => _selectedIndex;
                set
                {
                    _selectedIndex = value;
                    OnPropertyChanged();
                    // ReSharper disable ExplicitCallerInfoArgument
                    OnPropertyChanged(nameof(CurrentHeader));
                    OnPropertyChanged(nameof(CurrentContent));
                    // ReSharper restore ExplicitCallerInfoArgument
                }
            }

            public int Count => _items.Count;
            public string CurrentIndexText => null;
            public object CurrentHeader => _items[SelectedIndex].header;
            public object CurrentContent => _items[SelectedIndex].content;

            public event PropertyChangedEventHandler PropertyChanged;

            private void OnPropertyChanged([CallerMemberName] string propertyName = null)
            {
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
            }
        }

        public class CompletionData : ICompletionData
        {
            public CompletionData(string display, string text)
            {
                Text = text;
                Content = display;
            }

            public IBitmap Image => null;

            public string Text { get; }

            // Use this property if you want to show a fancy UIElement in the list.
            public object Content { get; }

            public object Description => "Description for " + Text;

            public double Priority { get; } = 0;

            public void Complete(TextArea textArea, ISegment completionSegment,
                EventArgs insertionRequestEventArgs)
            {
                textArea.Document.Replace(completionSegment, Text);
            }
        }

        class ElementGenerator : VisualLineElementGenerator, IComparer<Pair>
        {
            public List<Pair> controls = new List<Pair>();

            /// <summary>
            /// Gets the first interested offset using binary search
            /// </summary>
            /// <returns>The first interested offset.</returns>
            /// <param name="startOffset">Start offset.</param>
            public override int GetFirstInterestedOffset(int startOffset)
            {
                int pos = controls.BinarySearch(new Pair(startOffset, null), this);
                if (pos < 0)
                    pos = ~pos;
                if (pos < controls.Count)
                    return controls[pos].Key;
                else
                    return -1;
            }

            public override VisualLineElement ConstructElement(int offset)
            {
                int pos = controls.BinarySearch(new Pair(offset, null), this);
                if (pos >= 0)
                    return new InlineObjectElement(0, controls[pos].Value);
                else
                    return null;
            }

            int IComparer<Pair>.Compare(Pair x, Pair y)
            {
                return x.Key.CompareTo(y.Key);
            }
        }
    }
}
