using System.Net;
using System.Text;
using System.Text.Json;
using SaySpan.Core;
int checks = 0;
void Check(bool condition, string message) { checks++; if (!condition) throw new Exception(message); }
var p = new Preferences();
Check(TranslationProvider.Target(p, "你好", "") == "en", "Chinese to English");
Check(TranslationProvider.Target(p, "Please meet 李 at the train station tomorrow.", "") == "zh", "A proper name does not change the dominant language");
Check(TranslationProvider.Target(p, "hello", "") == "zh", "English to Chinese");
Check(TranslationProvider.Target(p with { SecondLanguage = "ja" }, "こんにちは", "") == "en", "Japanese detection");
Check(TranslationProvider.Target(p with { FirstLanguage = "fr", SecondLanguage = "de" }, "bonjour", "") == "auto", "Latin pair needs model identification");
Check(TranslationProvider.NormalizeUrl("https://example.com/v1/chat/completions") == "https://example.com/v1", "API suffix normalization");
foreach (var url in new[] { "http://example.com", "https://key@example.com", "https://example.com?key=secret", "file:///tmp/test" }) {
    bool rejected = false; try { TranslationProvider.NormalizeUrl(url); } catch (ArgumentException) { rejected = true; } Check(rejected, "unsafe API URL accepted");
}
Check(TranslationProvider.Effort("unknown-model", "lowest") == null, "Unknown model defaults");
Check(TranslationProvider.Effort("model", "high") == "high", "Explicit effort");
var body = TranslationProvider.Body(p, "  One\n\nTwo\n", "en", out var target);
using var doc = JsonDocument.Parse(JsonSerializer.Serialize(body));
Check(doc.RootElement.GetProperty("messages")[1].GetProperty("content").GetString() == "  One\n\nTwo\n", "Formatting preserved in request");
Check(target == "zh", "Pair request target");
using var frames = new MemoryStream();
await Wire.Write(frames, "你好\n\nA", default); frames.Position = 0;
Check(await Wire.Read(frames, default) == "你好\n\nA", "Unicode IPC roundtrip");
foreach (var data in new[] { new byte[] { 255, 255, 255, 127 }, new byte[] { 3, 0, 0, 0 } }) {
    bool rejected = false; try { await Wire.Read(new MemoryStream(data), default); } catch (InvalidDataException) { rejected = true; } Check(rejected, "Invalid IPC length accepted");
}
var handler = new FakeHandler(); using var client = new HttpClient(handler); var provider = new TranslationProvider(client);
var translated = await provider.Translate(p, "", "  One\n\nTwo\n", "en", default);
Check(translated.Text == "  一\n\n二\n", "Provider output indentation/newlines preserved");
Check(handler.Uri!.AbsolutePath == "/api/chat" && handler.Authorization == null, "Ollama routing");
var online = p with { Provider = "online", OnlineUrl = "https://example.com/v1", OnlineModel = "unknown", Reasoning = "lowest" };
handler.Online = true;
await provider.Translate(online, "synthetic", "hello", "en", default);
Check(handler.Authorization == "Bearer synthetic", "API key header");
Check(!handler.Body.Contains("reasoning_effort") && !handler.Body.Contains("temperature"), "Compatible provider omitted unsupported sampling");
handler.Status = HttpStatusCode.Unauthorized;
bool failed = false; try { await provider.Translate(online, "synthetic", "hello", "en", default); } catch (HttpRequestException e) { failed = !e.Message.Contains("server-private-error"); }
Check(failed, "HTTP errors do not expose raw response");
using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
bool wasCancelled = false; try { await provider.Translate(p, "", "hello", "en", cancelled.Token); } catch (OperationCanceledException) { wasCancelled = true; }
Check(wasCancelled, "Provider cancellation");
Console.WriteLine($"{checks} translation and IPC checks passed");
sealed class FakeHandler : HttpMessageHandler {
    public Uri? Uri; public string? Authorization; public string Body = ""; public bool Online; public HttpStatusCode Status = HttpStatusCode.OK;
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
        token.ThrowIfCancellationRequested(); Uri = request.RequestUri; Authorization = request.Headers.Authorization?.ToString(); Body = await request.Content!.ReadAsStringAsync(token);
        var message = new { content = "  一\n\n二\n" };
        string json = Online ? JsonSerializer.Serialize(new { choices = new[] { new { message } } }) : JsonSerializer.Serialize(new { message });
        return new(Status) { Content = new StringContent(Status == HttpStatusCode.OK ? json : "server-private-error", Encoding.UTF8, "application/json") };
    }
}
