using Microsoft.Win32;
using SaySpan.Core;
using Forms = System.Windows.Forms;
namespace SaySpan;
static class CompanionTests
{
    public static void Run(string[] args) {
        // Runs only on an isolated CI Windows account; never on a developer desktop.
        if (Environment.GetEnvironmentVariable("CI") != "true") throw new InvalidOperationException("Companion self-tests require an isolated CI account.");
        var original = Store.Read();
        try {
            var before = original with { AutomaticSelection = false }; Store.Save(original, before);
            Store.Automatic(true);
            Store.Save(before, before with { CandidateColumns = 7 });
            if (!Store.Read().AutomaticSelection) throw new Exception("Stale settings overwrote live automatic translation.");
            const string endpoint = "http://127.0.0.1:48321/v1";
            Credentials.Save(endpoint, "synthetic-test-key");
            if (Credentials.Read(endpoint) != "synthetic-test-key" || Credentials.Read(endpoint + "/other").Length != 0) throw new Exception("Credential scoping failed.");
            Credentials.Save(endpoint, "");
            Forms.Application.EnableVisualStyles();
            using var http = new HttpClient(); using var settings = new SettingsWindow(new TranslationProvider(http));
            settings.Show(); Forms.Application.DoEvents();
            if (!settings.Visible || settings.Controls.OfType<Forms.TabControl>().Single().TabCount != 6) throw new Exception("Settings pages are missing.");
            settings.Close();
            using var card = new SelectionCard(new System.Drawing.Point(100, 100), () => { }, _ => { });
            if(args.Length>1) {
                foreach(var kind in new[] {"readonly", "editable", "password"}) {
                    using var fixture=System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(args[1]) { ArgumentList = {"--selection-fixture", kind} })!;
                    try {
                        for(int attempt=0;attempt<50;attempt++){fixture.Refresh();if(fixture.MainWindowHandle!=IntPtr.Zero)break;System.Threading.Thread.Sleep(100);}
                        System.Threading.Thread.Sleep(300);fixture.Refresh();
                        var trace=new List<string>();
                        var selected=SelectionMonitor.ReadSelection(new System.Drawing.Point(140,150),fixture.MainWindowHandle,trace.Add);
                        if(kind=="readonly" && selected?.Text!="Line one")throw new Exception("UI Automation could not read the read-only fixture selection. " + string.Join("; ",trace));
                        if(kind!="readonly" && selected!=null)throw new Exception("Selection translation accepted an editable or password field.");
                    } finally {fixture.Kill();fixture.WaitForExit();}
                }
            }
            card.Show(); card.Loading("One\n\nTwo"); card.Result(new("一\n\n二", "zh")); Forms.Application.DoEvents(); card.Close();
        } finally { var now = Store.Read(); Store.Save(now, original); }
    }
}
