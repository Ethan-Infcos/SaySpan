using System.IO.Pipes;
using System.Security.Principal;
using SaySpan.Core;
using Forms = System.Windows.Forms;
namespace SaySpan;

static class Program
{
    public static readonly string PipeName = "SaySpan.v1." + WindowsIdentity.GetCurrent().User!.Value + "." + System.Diagnostics.Process.GetCurrentProcess().SessionId;
    [STAThread] static void Main(string[] args) {
        if (args.Contains("--self-test")) {
            try { CompanionTests.Run(args); }
            catch(Exception error) {
                if(Environment.GetEnvironmentVariable("CI")=="true")File.WriteAllText(System.IO.Path.Combine(AppContext.BaseDirectory,"self-test.log"),error.ToString());
                Environment.ExitCode=1;
            }
            return;
        }
        using var mutex = new Mutex(true, @"Local\" + PipeName, out bool first);
        if (!first) {
            if (!args.Contains("--background")) {
                try { using var pipe = new NamedPipeClientStream(".", PipeName, PipeDirection.InOut, PipeOptions.CurrentUserOnly);
                    pipe.Connect(2000); Wire.Write(pipe, "settings", CancellationToken.None).GetAwaiter().GetResult(); }
                catch (IOException) { } catch (TimeoutException) { }
            }
            return;
        }
        Forms.Application.SetHighDpiMode(Forms.HighDpiMode.PerMonitorV2);
        Forms.Application.EnableVisualStyles();
        Forms.Application.SetCompatibleTextRenderingDefault(false);
        using var app = new Companion(!args.Contains("--background"));
        Forms.Application.Run(app);
    }
}
sealed class Companion : Forms.ApplicationContext
{
    readonly Forms.Control dispatcher = new();
    readonly CancellationTokenSource stopping = new();
    readonly HttpClient http = new(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(90) };
    readonly Forms.NotifyIcon tray;
    readonly SelectionMonitor selection;
    SettingsWindow? settings;
    public Companion(bool show) {
        _ = dispatcher.Handle;
        var provider = new TranslationProvider(http);
        tray = new Forms.NotifyIcon { Icon = System.Drawing.SystemIcons.Application, Text = Store.Brand, Visible = true };
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add(Store.T("Settings…", "设置…"), null, (_, _) => ShowSettings());
        menu.Items.Add(Store.T("Exit companion", "退出辅助程序"), null, (_, _) => ExitThread());
        tray.ContextMenuStrip = menu; tray.DoubleClick += (_, _) => ShowSettings();
        selection = new SelectionMonitor(dispatcher, provider, stopping.Token);
        _ = Serve(provider, stopping.Token);
        if (show) ShowSettings();
    }
    void ShowSettings() {
        if (settings == null || settings.IsDisposed) settings = new SettingsWindow(new TranslationProvider(http));
        settings.Show(); settings.Activate();
    }
    async Task Serve(TranslationProvider provider, CancellationToken token) {
        while (!token.IsCancellationRequested) {
            var pipe = new NamedPipeServerStream(Program.PipeName, PipeDirection.InOut, 16, PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
            try { await pipe.WaitForConnectionAsync(token); _ = Handle(pipe, provider, token); }
            catch (OperationCanceledException) { pipe.Dispose(); break; }
            catch (IOException) { pipe.Dispose(); await Task.Delay(250, token); }
        }
    }
    async Task Handle(NamedPipeServerStream pipe, TranslationProvider provider, CancellationToken stoppingToken) {
        using (pipe)
        using (var request = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken)) {
            request.CancelAfter(TimeSpan.FromSeconds(95));
            var token = request.Token;
            try {
                var operation = await Wire.Read(pipe, token);
                if (operation == "settings") { dispatcher.BeginInvoke(ShowSettings); return; }
                if (operation != "translate") throw new InvalidDataException("Unknown IPC operation.");
                var source = await Wire.Read(pipe, token); var text = await Wire.Read(pipe, token);
                var preferences = Store.Read();
                // Client closes its connection when its draft changes. Cancel the HTTP request too.
                var disconnect = new byte[1];
                var watching = pipe.ReadAsync(disconnect, token).AsTask();
                var translation = provider.Translate(preferences, preferences.Provider == "online" ? Credentials.Read(preferences.OnlineUrl) : "", text, source, token);
                if (await Task.WhenAny(translation, watching) == watching) { request.Cancel(); try { await translation; } catch (Exception) { } return; }
                var result = await translation;
                await Wire.Write(pipe, "ok", token); await Wire.Write(pipe, result.Target, token); await Wire.Write(pipe, result.Text, token);
                request.Cancel();
            } catch (Exception ex) when (ex is not OutOfMemoryException) {
                try { await Wire.Write(pipe, "error", token); await Wire.Write(pipe, "", token); await Wire.Write(pipe, FriendlyError(ex), token); } catch (Exception) { }
            }
        }
    }
    public static string FriendlyError(Exception error) => error switch {
        OperationCanceledException => Store.T("Translation timed out. Try again.", "翻译超时，请重试。"),
        HttpRequestException => Store.T("Cannot translate. Check the service, URL, API key, model and reasoning setting in Settings → Models.", "翻译失败，请检查设置 → 模型中的服务、地址、API 密钥、模型和推理等级。"),
        _ => Store.T("Translation is unavailable. Check Settings → Models.", "翻译不可用，请检查设置 → 模型。")
    };
    protected override void ExitThreadCore() { stopping.Cancel(); selection.Dispose(); tray.Visible = false; tray.Dispose(); settings?.Close(); http.Dispose(); dispatcher.Dispose(); base.ExitThreadCore(); }
}
