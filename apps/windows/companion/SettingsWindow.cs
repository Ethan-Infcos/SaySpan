using SaySpan.Core;
using Forms = System.Windows.Forms;
using System.Drawing;
namespace SaySpan;
sealed class SettingsWindow : Forms.Form
{
    readonly Preferences initial = Store.Read();
    readonly TranslationProvider provider;
    readonly CancellationTokenSource lifetime = new();
    readonly Forms.ComboBox backend = Combo(["Ollama", "OpenAI-compatible API"]);
    readonly Forms.TextBox localUrl = new(), onlineUrl = new(), apiKey = new() { UseSystemPasswordChar = true };
    readonly Forms.ComboBox localModel = new() { DropDownStyle = Forms.ComboBoxStyle.DropDown }, onlineModel = new() { DropDownStyle = Forms.ComboBoxStyle.DropDown };
    readonly Forms.ComboBox reasoning = Combo(TranslationProvider.ReasoningOptions);
    readonly Forms.ComboBox first = Combo(Preferences.LanguageNames), second = Combo(Preferences.LanguageNames);
    readonly Forms.NumericUpDown columns = new() { Minimum = 3, Maximum = 9 };
    readonly Forms.CheckBox learning = new(), enabled = new(), automatic = new();
    readonly Forms.ComboBox language = Combo(["System / 跟随系统", "English", "简体中文"]);
    readonly Forms.TextBox prompt = new() { Multiline = true, ScrollBars = Forms.ScrollBars.Vertical, Height = 260, AcceptsReturn = true };
    readonly Forms.Label status = new() { AutoSize = true, MaximumSize = new Size(650, 0), ForeColor = Color.DimGray };
    static Forms.ComboBox Combo(string[] values) { var c = new Forms.ComboBox { DropDownStyle = Forms.ComboBoxStyle.DropDownList }; c.Items.AddRange(values); c.SelectedIndex = 0; return c; }
    public SettingsWindow(TranslationProvider provider) {
        this.provider = provider;
        Text = Store.Brand + " — " + Store.T("Settings", "设置"); MinimumSize = new Size(700, 600); Size = new Size(790, 750);
        StartPosition = Forms.FormStartPosition.CenterScreen; Font = new Font("Segoe UI", 10); AutoScaleMode = Forms.AutoScaleMode.Dpi;
        var tabs = new Forms.TabControl { Dock = Forms.DockStyle.Fill };
        var models = Page(tabs, Store.T("Models", "模型"));
        Row(models, Store.T("Translation service", "翻译服务"), backend);
        Row(models, Store.T("Ollama URL", "Ollama 地址"), localUrl);
        Row(models, Store.T("Ollama model", "Ollama 模型"), localModel);
        Button(models, Store.T("Refresh local models", "刷新本地模型"), async () => await RefreshModels(false));
        Row(models, Store.T("API base URL", "API 地址"), onlineUrl);
        Row(models, Store.T("API key", "API 密钥"), apiKey);
        Note(models, Store.T("Leave the key blank to keep the saved key for this URL. Keys are encrypted for your Windows account.", "密钥留空会保留此地址已保存的密钥。密钥使用 Windows 账户加密。"));
        Button(models, Store.T("Remove saved key for this URL", "删除此地址的已保存密钥"), () => { Credentials.Save(onlineUrl.Text, ""); apiKey.Clear(); status.Text = Store.T("Key removed.", "密钥已删除。"); return Task.CompletedTask; });
        Row(models, Store.T("Online model", "在线模型"), onlineModel);
        Button(models, Store.T("Refresh online models", "刷新在线模型"), async () => await RefreshModels(true));
        Row(models, Store.T("Reasoning effort", "推理等级"), reasoning);
        Note(models, Store.T("Lowest uses a known model's minimum effort; unknown models use the service default. Choose Default if your provider rejects reasoning parameters.", "最低档使用已知模型的最低推理等级；未知模型采用服务默认值。不支持推理参数时请选择 default。"));
        Button(models, Store.T("Test translation", "测试翻译"), async () => { var p = ReadControls(); var result = await provider.Translate(p, Key(p), "Hello, world!", "en", lifetime.Token); status.Text = result.Text; });
        var input = Page(tabs, Store.T("Input", "输入"));
        Row(input, Store.T("Candidates per row", "每行候选数"), columns); Row(input, Store.T("Remember frequent candidates", "记忆常用候选"), learning);
        Button(input, Store.T("Clear learned candidates", "清空候选记忆"), () => { if (Forms.MessageBox.Show(this, Store.T("Clear all learned candidate frequencies?", "清空所有候选词频记忆？"), Store.Brand, Forms.MessageBoxButtons.YesNo) == Forms.DialogResult.Yes) Store.ClearLearning(); return Task.CompletedTask; });
        Note(input, Store.T("Tap Shift to switch languages. Hold Shift for uppercase letters or text selection. Caps Lock only changes capitalization. While composing, a Shift tap inserts the selected source text before switching.\n\nSpace chooses a candidate. PgUp/PgDn expands candidates; arrows move the highlight. Enter keeps unselected spelling as Latin text, then inserts the source sentence. Tab inserts a ready translation. Ctrl+A/C/X/V/Z edit the draft. Clearing the sentence closes the panel.", "短按 Shift 切换语言；按住 Shift 输入大写字母或选择文字。Caps Lock 只控制大小写。组句中短按 Shift 会先确认候选并将原文上屏，再切换语言。\n\n空格选词；PgUp/PgDn 展开候选，方向键移动高亮。Enter 将未选拼音作为字母加入句子，再次 Enter 原文上屏。Tab 将已完成的译文上屏。Ctrl+A/C/X/V/Z 编辑组句。清空句子会关闭面板。"));
        var languages = Page(tabs, Store.T("Languages", "语言")); Row(languages, Store.T("First language", "第一语言"), first); Row(languages, Store.T("Second language", "第二语言"), second);
        Note(languages, Store.T("The first language is used initially. Shift toggles between the pair. Input and selection translation automatically translate into the other language. English is entered directly. Chinese and Japanese use candidates. Other languages use Windows keyboard layouts where available; Korean composition requires the Windows Korean input method.", "默认使用第一语言，Shift 在两种语言之间切换。输入翻译和划词翻译自动译成另一种语言。英文直接输入，中文和日文使用候选。其他语言使用可用的 Windows 键盘布局；韩语组字需使用 Windows 韩语输入法。"));
        var selection = Page(tabs, Store.T("Selection", "划词")); Row(selection, Store.T("Enable selection translation", "启用划词翻译"), enabled); Row(selection, Store.T("Translate automatically", "自动显示译文"), automatic);
        Note(selection, Store.T("Select text outside an editable field. A stationary Translate button appears, or a translation card when automatic translation is enabled. Copy is in the top right. Click elsewhere to dismiss, then reselect to retry. The source is never replaced. Apps must expose their selected text to Windows accessibility. Online translation sends selected text to your configured service.", "在输入框之外选择文字，会出现固定位置的翻译按钮；开启自动翻译后直接显示译文。右上角可复制，点击其他位置关闭，重新选择可重试。不会替换原文。软件需向 Windows 辅助功能公开选中文字。在线翻译会将选中文字发送给配置的服务。"));
        var prompts = Page(tabs, Store.T("Prompt", "提示词")); Row(prompts, Store.T("Translation instructions", "翻译指令"), prompt);
        Button(prompts, Store.T("Restore default prompt", "恢复默认提示词"), () => { prompt.Text = Preferences.DefaultPrompt; return Task.CompletedTask; });
        Note(prompts, Store.T("Used for composition and selection. Direction and formatting-preservation instructions are added automatically.", "输入和划词翻译共用。翻译方向与格式保留规则会自动附加。"));
        var ui = Page(tabs, Store.T("Interface", "界面")); Row(ui, Store.T("Display language", "显示语言"), language);
        Note(ui, Store.T("Reopen Settings to apply its display language. The companion starts when you sign in. Settings are also available from the Start menu and the notification-area icon.", "重新打开设置后界面语言生效。辅助程序会在登录时启动。也可从开始菜单或系统托盘图标打开设置。"));
        var footer = new Forms.FlowLayoutPanel { Dock = Forms.DockStyle.Bottom, Height = 90, Padding = new Forms.Padding(12), FlowDirection = Forms.FlowDirection.LeftToRight };
        var save = new Forms.Button { Text = Store.T("Save", "保存"), AutoSize = true };
        save.Click += (_, _) => { try { var p = ReadControls(); p.Validate(); if (apiKey.Text.Length > 0) Credentials.Save(p.OnlineUrl, apiKey.Text); Store.Save(initial, p); Close(); } catch (Exception e) { status.Text = e.Message; } };
        var cancel = new Forms.Button { Text = Store.T("Cancel", "取消"), AutoSize = true }; cancel.Click += (_, _) => Close();
        footer.Controls.AddRange([save, cancel, status]); Controls.Add(tabs); Controls.Add(footer);
        backend.SelectedIndex = initial.Provider == "online" ? 1 : 0; localUrl.Text = initial.OllamaUrl; localModel.Text = initial.OllamaModel;
        onlineUrl.Text = initial.OnlineUrl; onlineModel.Text = initial.OnlineModel; reasoning.SelectedItem = initial.Reasoning;
        first.SelectedIndex = Array.IndexOf(Preferences.Languages, initial.FirstLanguage); second.SelectedIndex = Array.IndexOf(Preferences.Languages, initial.SecondLanguage);
        columns.Value = Math.Clamp(initial.CandidateColumns, 3, 9); learning.Checked = initial.Learning; enabled.Checked = initial.SelectionEnabled; automatic.Checked = initial.AutomaticSelection;
        language.SelectedIndex = initial.InterfaceLanguage == "en" ? 1 : initial.InterfaceLanguage == "zh" ? 2 : 0; prompt.Text = initial.Prompt;
        onlineUrl.TextChanged += (_, _) => apiKey.Clear();
        FormClosed += (_, _) => lifetime.Cancel();
    }
    Preferences ReadControls() => initial with { Provider = backend.SelectedIndex == 1 ? "online" : "ollama", OllamaUrl = localUrl.Text.Trim(), OllamaModel = localModel.Text.Trim(), OnlineUrl = onlineUrl.Text.Trim(), OnlineModel = onlineModel.Text.Trim(), Reasoning = reasoning.Text,
        FirstLanguage = Preferences.Languages[Math.Max(0, first.SelectedIndex)], SecondLanguage = Preferences.Languages[Math.Max(0, second.SelectedIndex)], CandidateColumns = (int)columns.Value, Learning = learning.Checked, SelectionEnabled = enabled.Checked, AutomaticSelection = automatic.Checked,
        InterfaceLanguage = language.SelectedIndex == 1 ? "en" : language.SelectedIndex == 2 ? "zh" : "auto", Prompt = prompt.Text };
    string Key(Preferences p) => p.Provider == "online" ? apiKey.Text.Length > 0 ? apiKey.Text : Credentials.Read(p.OnlineUrl) : "";
    async Task RefreshModels(bool online) {
        var p = ReadControls() with { Provider = online ? "online" : "ollama" };
        var list = await provider.Models(p, Key(p), lifetime.Token);
        if (IsDisposed) return;
        var box = online ? onlineModel : localModel; var previous = box.Text; box.Items.Clear(); box.Items.AddRange(list); box.Text = previous;
        status.Text = Store.T($"Found {list.Length} models.", $"找到 {list.Length} 个模型。");
    }
    static Forms.TableLayoutPanel Page(Forms.TabControl tabs, string title) {
        var tab = new Forms.TabPage(title) { AutoScroll = true, Padding = new Forms.Padding(16) };
        var grid = new Forms.TableLayoutPanel { Dock = Forms.DockStyle.Top, AutoSize = true, ColumnCount = 1, AutoSizeMode = Forms.AutoSizeMode.GrowAndShrink };
        grid.ColumnStyles.Add(new Forms.ColumnStyle(Forms.SizeType.Percent, 100)); tab.Controls.Add(grid); tabs.TabPages.Add(tab); return grid;
    }
    static void Row(Forms.TableLayoutPanel p, string label, Forms.Control c) {
        p.Controls.Add(new Forms.Label { Text = label, AutoSize = true, Margin = new Forms.Padding(0, 12, 0, 4) }); c.Dock = Forms.DockStyle.Top; p.Controls.Add(c);
    }
    static void Note(Forms.TableLayoutPanel p, string text) => p.Controls.Add(new Forms.Label { Text = text, AutoSize = true, MaximumSize = new Size(650, 0), ForeColor = Color.DimGray, Margin = new Forms.Padding(0, 12, 0, 8) });
    void Button(Forms.TableLayoutPanel p, string text, Func<Task> action) {
        var b = new Forms.Button { Text = text, AutoSize = true, Margin = new Forms.Padding(0, 8, 0, 8) };
        b.Click += async (_, _) => { b.Enabled = false; try { await action(); } catch (Exception e) { if (!IsDisposed) status.Text = e is ArgumentException ? e.Message : Companion.FriendlyError(e); } finally { if (!IsDisposed) b.Enabled = true; } }; p.Controls.Add(b);
    }
}
