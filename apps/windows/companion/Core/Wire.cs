using System.Buffers.Binary;
using System.Text;
namespace SaySpan.Core;
// v1: little-endian UTF-16 byte length + payload, bounded before allocation.
public static class Wire
{
    public static async Task<string> Read(Stream stream, CancellationToken token)
    {
        var header = new byte[4]; await stream.ReadExactlyAsync(header, token);
        int length = BinaryPrimitives.ReadInt32LittleEndian(header);
        if (length < 0 || length > 131072 || length % 2 != 0) throw new InvalidDataException("Invalid IPC frame.");
        var data = new byte[length]; await stream.ReadExactlyAsync(data, token);
        return new UnicodeEncoding(false, false, true).GetString(data);
    }
    public static async Task Write(Stream stream, string value, CancellationToken token)
    {
        var data = Encoding.Unicode.GetBytes(value);
        if (data.Length > 131072) throw new InvalidDataException("IPC frame too large.");
        var header = new byte[4]; BinaryPrimitives.WriteInt32LittleEndian(header, data.Length);
        await stream.WriteAsync(header, token); await stream.WriteAsync(data, token); await stream.FlushAsync(token);
    }
}
