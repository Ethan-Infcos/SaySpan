using System.Runtime.InteropServices;
using System.Windows.Automation;
using SaySpan.Core;
using Forms = System.Windows.Forms;
using Drawing = System.Drawing;
namespace SaySpan;

sealed record SelectedText(string Text, Drawing.Point Position, IntPtr Window);
sealed class SelectionMonitor : IDisposable
{
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out Drawing.Point point);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    readonly Forms.Control dispatcher;
    readonly TranslationProvider provider;
    readonly CancellationToken token;
    SelectionCard? card;
    CancellationTokenSource? translation;
    string current = "";
    IntPtr currentWindow;
    int revision;
    bool disposed;
    public SelectionMonitor(Forms.Control dispatcher, TranslationProvider provider, CancellationToken token) {
        this.dispatcher = dispatcher; this.provider = provider; this.token = token;
        // UI Automation can block in an application provider. Keep it off the UI and IME threads.
        _ = Task.Run(Monitor, token);
    }
    void Post(Action action) { if (!disposed && !dispatcher.IsDisposed) try { dispatcher.BeginInvoke(action); } catch (InvalidOperationException) { } }
    async Task Monitor() {
        bool wasMouseDown = false, wasShift = false;
        long settledAt = 0; Drawing.Point selectedAt = default;
        while (!token.IsCancellationRequested && !disposed) {
            try {
                await Task.Delay(100, token);
                bool mouseDown = GetAsyncKeyState(1) < 0, shift = GetAsyncKeyState(0x10) < 0;
                var foreground = GetForegroundWindow(); GetWindowThreadProcessId(foreground, out uint process);
                if (process == Environment.ProcessId) { wasMouseDown = mouseDown; wasShift = shift; continue; }
                if (!Store.Read().SelectionEnabled || Store.Composing()) { Post(Clear); settledAt = 0; wasMouseDown = mouseDown; wasShift = shift; continue; }
                if (mouseDown && !wasMouseDown) Post(Clear);
                if (wasMouseDown && !mouseDown || wasShift && !shift) { GetCursorPos(out selectedAt); settledAt = Environment.TickCount64 + 350; }
                wasMouseDown = mouseDown; wasShift = shift;
                if (mouseDown || settledAt == 0 || Environment.TickCount64 < settledAt) continue;
                settledAt = 0;
                var found = ReadSelection(selectedAt, foreground);
                if (found == null) { Post(Clear); continue; }
                if (GetForegroundWindow() != foreground || Store.Composing()) continue;
                Post(() => Show(found));
            } catch (OperationCanceledException) { break; }
            catch (Exception e) when (e is ElementNotAvailableException or InvalidOperationException or COMException or UnauthorizedAccessException) { Post(Clear); }
        }
    }
    internal static SelectedText? ReadSelection(Drawing.Point point, IntPtr foreground) {
        // Hit-test the selected content first; focused controls may still be an unrelated editor.
        var hit = AutomationElement.FromPoint(new System.Windows.Point(point.X, point.Y));
        foreach (var start in new[] { hit, AutomationElement.FocusedElement }) {
            var node = start;
            for (int depth = 0; node != null && depth < 9; depth++, node = TreeWalker.ControlViewWalker.GetParent(node)) {
                var properties = node.Current;
                if (properties.ProcessId == Environment.ProcessId || properties.IsPassword || properties.ControlType == ControlType.Edit) break;
                GetWindowThreadProcessId(foreground, out uint pid);
                if (properties.ProcessId != pid) break;
                if (!node.TryGetCurrentPattern(TextPattern.Pattern, out var value)) continue;
                var pattern = (TextPattern)value;
                foreach (var range in pattern.GetSelection()) {
                    var readOnly = range.GetAttributeValue(TextPattern.IsReadOnlyAttribute);
                    if (readOnly is bool editable && !editable) continue;
                    var text = range.GetText(8193);
                    if (string.IsNullOrWhiteSpace(text) || text.Length > 8192) continue;
                    // Use the first selection rectangle once; never chase later mouse movement.
                    var rectangles = range.GetBoundingRectangles();
                    var position = rectangles.Length > 0 ? new Drawing.Point((int)rectangles[0].Left, (int)rectangles[0].Bottom + 8) : new Drawing.Point(point.X, point.Y + 12);
                    return new(text, position, foreground);
                }
            }
        }
        return null;
    }
    void Show(SelectedText selected) {
        if (disposed || Store.Composing() || !Store.Read().SelectionEnabled || GetForegroundWindow() != selected.Window) return;
        if (current == selected.Text && currentWindow == selected.Window && card is { IsDisposed: false }) return;
        Clear(); current = selected.Text; currentWindow = selected.Window;
        card = new SelectionCard(selected.Position, () => _ = Translate(), value => Store.Automatic(value));
        card.Show();
        if (Store.Read().AutomaticSelection) _ = Translate();
    }
    async Task Translate() {
        if (card == null || string.IsNullOrWhiteSpace(current)) return;
        translation?.Cancel(); translation?.Dispose(); translation = CancellationTokenSource.CreateLinkedTokenSource(token);
        var cancellation = translation.Token; int request = ++revision; var view = card;
        view.Loading(current);
        try {
            var p = Store.Read(); var result = await provider.Translate(p, p.Provider == "online" ? Credentials.Read(p.OnlineUrl) : "", current, "", cancellation);
            if (!cancellation.IsCancellationRequested && request == revision && !view.IsDisposed && !Store.Composing()) view.Result(result);
        } catch (Exception ex) { if (!cancellation.IsCancellationRequested && request == revision && !view.IsDisposed) view.Error(Companion.FriendlyError(ex)); }
    }
    void Clear() { ++revision; translation?.Cancel(); translation?.Dispose(); translation = null; card?.Close(); card = null; current = ""; currentWindow = IntPtr.Zero; }
    public void Dispose() { disposed = true; Clear(); }
}
sealed class SelectionCard : Forms.Form
{
    readonly Forms.Label title = new() { AutoSize = true };
    readonly Forms.TextBox result = new() { Multiline = true, ReadOnly = true, BorderStyle = Forms.BorderStyle.None, ScrollBars = Forms.ScrollBars.Vertical, Dock = Forms.DockStyle.Fill, BackColor = Drawing.Color.White };
    readonly Forms.Label source = new() { AutoSize = true, MaximumSize = new Drawing.Size(480, 70), ForeColor = Drawing.Color.DimGray };
    readonly Forms.Button copy = new() { Text = "⧉", Width = 32, Height = 28, Enabled = false, AccessibleName = Store.T("Copy translation", "复制译文") };
    readonly Forms.CheckBox automatic = new() { Text = Store.T("Automatic", "自动翻译"), AutoSize = true };
    readonly Forms.Button translate = new() { Text = Store.T("Translate", "译"), Dock = Forms.DockStyle.Fill, AutoSize = true };
    readonly Drawing.Point origin;
    bool expanded;
    public SelectionCard(Drawing.Point position, Action start, Action<bool> toggle) {
        origin = position; ShowInTaskbar = false; TopMost = true; FormBorderStyle = Forms.FormBorderStyle.FixedSingle; ControlBox = false;
        StartPosition = Forms.FormStartPosition.Manual; Font = new Drawing.Font("Segoe UI", 11); BackColor = Drawing.Color.White;
        ClientSize = new Drawing.Size(100, 34); Controls.Add(translate); translate.Click += (_, _) => start();
        automatic.Checked = Store.Read().AutomaticSelection;
        automatic.CheckedChanged += (_, _) => toggle(automatic.Checked);
        copy.Click += (_, _) => { if (result.Text.Length > 0) try { Forms.Clipboard.SetText(result.Text); } catch (ExternalException) { } };
        Location = Clamp(position, Size);
    }
    protected override bool ShowWithoutActivation => true;
    protected override Forms.CreateParams CreateParams { get { var p = base.CreateParams; p.ExStyle |= 0x08000000 | 0x80; return p; } }
    protected override void WndProc(ref Forms.Message m) { if (m.Msg == 0x21) { m.Result = new IntPtr(3); return; } base.WndProc(ref m); }
    static Drawing.Point Clamp(Drawing.Point p, Drawing.Size size) { var work = Forms.Screen.FromPoint(p).WorkingArea; return new(Math.Clamp(p.X, work.Left, Math.Max(work.Left, work.Right - size.Width)), Math.Clamp(p.Y, work.Top, Math.Max(work.Top, work.Bottom - size.Height))); }
    public void Loading(string text) {
        if (!expanded) {
            expanded = true; Controls.Clear(); ClientSize = new Drawing.Size(540, 330); Padding = new Forms.Padding(16);
            var header = new Forms.FlowLayoutPanel { Dock = Forms.DockStyle.Top, Height = 40 };
            title.Text = Store.Brand; title.Margin = new Forms.Padding(0, 4, 24, 0); header.Controls.AddRange([title, automatic, copy]);
            var preview = new Forms.Panel { Dock = Forms.DockStyle.Top, Height = 70 }; preview.Controls.Add(source);
            Controls.Add(result); Controls.Add(preview); Controls.Add(header); Location = Clamp(origin, Size);
        }
        source.Text = text; result.Text = Store.T("Translating…", "翻译中…"); copy.Enabled = false;
    }
    public void Result(TranslationResult translation) { title.Text = translation.Target == "auto" ? Store.T("Translation", "译文") : Preferences.Name(translation.Target); result.Text = translation.Text; copy.Enabled = true; }
    public void Error(string message) { result.Text = message; copy.Enabled = false; }
}
