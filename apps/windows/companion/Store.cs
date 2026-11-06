using Microsoft.Win32;
using SaySpan.Core;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
namespace SaySpan;

static class Store
{
    public const string Path = @"Software\SaySpan";
    public static string Brand { get; } = ReadBrand();
    static string ReadBrand() {
        var assembly = typeof(Store).Assembly;
        using var stream = assembly.GetManifestResourceStream(assembly.GetManifestResourceNames().Single(n => n.EndsWith("Branding.json")))!;
        using var json = JsonDocument.Parse(stream); return json.RootElement.GetProperty("name").GetString()!;
    }
    public static Preferences Read() {
        var defaults = new Preferences();
        var fields = new Dictionary<string, object?>();
        using var key = Registry.CurrentUser.OpenSubKey(Path);
        foreach (var property in typeof(Preferences).GetProperties()) {
            object? value = key?.GetValue(property.Name) ?? property.GetValue(defaults);
            if (property.PropertyType == typeof(bool)) value = value is bool b ? b : Convert.ToInt32(value) != 0;
            fields[property.Name] = value;
        }
        try { return JsonSerializer.Deserialize<Preferences>(JsonSerializer.Serialize(fields)) ?? defaults; }
        catch (JsonException) { return defaults; }
    }
    // Only changed fields are written. A stale Settings window cannot overwrite
    // the automatic-translation switch changed in a live selection card.
    public static void Save(Preferences before, Preferences after) {
        after.Validate();
        using var key = Registry.CurrentUser.CreateSubKey(Path);
        foreach (var property in typeof(Preferences).GetProperties()) {
            var value = property.GetValue(after);
            if (Equals(value, property.GetValue(before))) continue;
            key.SetValue(property.Name, value is bool b ? b ? 1 : 0 : value!);
        }
    }
    public static void Automatic(bool enabled) {
        using var key = Registry.CurrentUser.CreateSubKey(Path); key.SetValue(nameof(Preferences.AutomaticSelection), enabled ? 1 : 0);
    }
    public static bool Composing() {
        using var key = Registry.CurrentUser.OpenSubKey(Path + @"\Activity");
        if (key == null) return false;
        foreach (var name in key.GetValueNames())
            if (key.GetValue(name) is long time && Environment.TickCount64 - time is >= 0 and < 1800) return true;
        return false;
    }
    public static bool Chinese => Read().InterfaceLanguage switch { "zh" => true, "en" => false, _ => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "zh" };
    public static string T(string en, string zh) => Chinese ? zh : en;
    public static void ClearLearning() => Registry.CurrentUser.DeleteSubKeyTree(Path + @"\Learning", false);
}

static class Credentials
{
    [StructLayout(LayoutKind.Sequential)] struct Blob { public int Length; public IntPtr Data; }
    [DllImport("crypt32.dll", SetLastError = true)] static extern bool CryptProtectData(ref Blob input, string? description, IntPtr entropy, IntPtr reserved, IntPtr prompt, uint flags, out Blob output);
    [DllImport("crypt32.dll", SetLastError = true)] static extern bool CryptUnprotectData(ref Blob input, IntPtr description, IntPtr entropy, IntPtr reserved, IntPtr prompt, uint flags, out Blob output);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr value);
    static string Name(string url) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(TranslationProvider.NormalizeUrl(url))));
    static byte[] Protect(byte[] data, bool encrypt) {
        var input = new Blob { Length = data.Length, Data = Marshal.AllocHGlobal(data.Length) };
        try {
            Marshal.Copy(data, 0, input.Data, data.Length);
            Blob output;
            bool ok = encrypt ? CryptProtectData(ref input, null, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 1, out output) : CryptUnprotectData(ref input, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 1, out output);
            if (!ok) throw new CryptographicException("Windows could not protect or read the API key.");
            try { var result = new byte[output.Length]; Marshal.Copy(output.Data, result, 0, result.Length); return result; }
            finally { LocalFree(output.Data); }
        } finally { Marshal.FreeHGlobal(input.Data); }
    }
    public static string Read(string url) {
        using var key = Registry.CurrentUser.OpenSubKey(Store.Path + @"\Credentials");
        if (key?.GetValue(Name(url)) is not byte[] value) return "";
        var bytes = Protect(value, false); try { return Encoding.UTF8.GetString(bytes); } finally { CryptographicOperations.ZeroMemory(bytes); }
    }
    public static void Save(string url, string value) {
        using var key = Registry.CurrentUser.CreateSubKey(Store.Path + @"\Credentials");
        if (value.Length == 0) { key.DeleteValue(Name(url), false); return; }
        var bytes = Encoding.UTF8.GetBytes(value);
        try { key.SetValue(Name(url), Protect(bytes, true), RegistryValueKind.Binary); }
        finally { CryptographicOperations.ZeroMemory(bytes); }
    }
}
