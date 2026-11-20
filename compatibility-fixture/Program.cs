using System.Collections.Concurrent;
using System.IO.Compression;
using System.Reflection;
using System.Resources;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CompatibilityFixture;

// A benign, manually launched regression fixture; WinExe means no console window.
// It does not conceal its process, persist, use the network, or run other programs.
internal static class Program
{
    private const string Version = "1.0.0";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    private static async Task<int> Main(string[] args)
    {
        var output = Option(args, "--out") ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "AdvancedEXEProtector", "FixtureReports", "latest.json");
        var baseline = Option(args, "--compare");
        var tests = new List<CaseResult>();
        await Test(tests, "arithmetic-and-branches", () => Task.FromResult(Arithmetic()));
        await Test(tests, "unicode-and-encoding", () => Task.FromResult(Unicode()));
        await Test(tests, "json-roundtrip", () => Task.FromResult(JsonRoundTrip()));
        await Test(tests, "compression-roundtrip", () => Task.FromResult(Compression()));
        await Test(tests, "sha256-hmac", () => Task.FromResult(HashAndHmac()));
        await Test(tests, "aesgcm-roundtrip", () => Task.FromResult(AesRoundTrip()));
        await Test(tests, "generic-dispatch", () => Task.FromResult(Generics()));
        await Test(tests, "reflection-invocation", () => Task.FromResult(ReflectionTest()));
        await Test(tests, "embedded-resource", () => Task.FromResult(ResourceTest()));
        await Test(tests, "exceptions-and-finally", () => Task.FromResult(Exceptions()));
        await Test(tests, "file-io-roundtrip", () => Task.FromResult(FileIo()));
        await Test(tests, "async-concurrency", AsyncWork);
        await Test(tests, "windows-interop", () => Task.FromResult(Interop()));

        var passed = tests.All(t => t.Passed);
        var overall = Fingerprint(string.Join("\n", tests.OrderBy(t => t.Id, StringComparer.Ordinal)
            .Select(t => $"{t.Id}|{t.Passed}|{t.Fingerprint}")));
        var report = new Report(1, Version, DateTimeOffset.UtcNow, passed, overall, tests, null, null);
        var match = true;
        if (baseline is not null)
        {
            try
            {
                var original = JsonSerializer.Deserialize<Report>(await File.ReadAllTextAsync(baseline), JsonOptions)
                    ?? throw new InvalidDataException("Empty baseline.");
                var expected = original.Tests.OrderBy(t => t.Id).ToArray();
                var actual = tests.OrderBy(t => t.Id).ToArray();
                match = original.Passed && report.Passed &&
                    original.SchemaVersion == report.SchemaVersion &&
                    original.FixtureVersion == report.FixtureVersion &&
                    expected.Length == actual.Length &&
                    expected.Zip(actual).All(p => p.First.Id == p.Second.Id &&
                        p.First.Passed == p.Second.Passed &&
                        p.First.Fingerprint == p.Second.Fingerprint);
                report = report with { BaselineMatched = match };
            }
            catch (Exception ex)
            {
                match = false;
                report = report with { BaselineMatched = false, Error = $"{ex.GetType().Name}: {ex.Message}" };
            }
        }
        try
        {
            var path = Path.GetFullPath(output);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            await File.WriteAllTextAsync(path, JsonSerializer.Serialize(report, JsonOptions), Encoding.UTF8);
        }
        catch { return 3; }
        return passed && match ? 0 : 2;
    }

    private static string? Option(string[] args, string name)
    {
        for (int i = 0; i + 1 < args.Length; i++)
            if (args[i].Equals(name, StringComparison.OrdinalIgnoreCase)) return args[i + 1];
        return null;
    }

    private static async Task Test(List<CaseResult> cases, string id, Func<Task<string>> work)
    {
        try { cases.Add(new CaseResult(id, true, Fingerprint(await work()), null)); }
        catch (Exception ex) { cases.Add(new CaseResult(id, false, "", $"{ex.GetType().Name}: {ex.Message}")); }
    }

    private static string Fingerprint(string value) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));

    private static string Arithmetic()
    {
        long sum = 0;
        for (int i = 1; i <= 2000; i++)
            sum += i % 3 == 0 ? i * 7L : i % 5 == 0 ? -i * 2L : i;
        if (Gcd(123456, 7890) != 6) throw new Exception("GCD regression.");
        return $"{sum}:{Gcd(123456, 7890)}:{Fib(20)}";
    }
    private static int Gcd(int a, int b) { while (b != 0) (a, b) = (b, a % b); return a; }
    private static int Fib(int n) => n < 2 ? n : Fib(n - 1) + Fib(n - 2);

    private static string Unicode()
    {
        const string input = "Protección • שלום • 日本語 • 🔒 • naïve";
        var restored = Encoding.UTF8.GetString(Encoding.UTF8.GetBytes(input));
        if (restored != input) throw new InvalidDataException("UTF8 changed.");
        return restored.Normalize(NormalizationForm.FormC);
    }

    public enum Level { Low, Medium, High }
    public sealed record Sample(string Name, int Count, Level Level, List<string> Tags);
    private static string JsonRoundTrip()
    {
        var value = new Sample("sample", 42, Level.High, new List<string> { "alpha", "βeta" });
        var json = JsonSerializer.Serialize(value, JsonOptions);
        var recovered = JsonSerializer.Deserialize<Sample>(json, JsonOptions);
        if (recovered is null || recovered.Name != value.Name || recovered.Count != value.Count ||
            recovered.Level != value.Level || !recovered.Tags.SequenceEqual(value.Tags))
            throw new InvalidDataException("JSON regression.");
        return json;
    }

    private static string Compression()
    {
        byte[] input = Encoding.UTF8.GetBytes(string.Concat(Enumerable.Repeat("DATA-1234-✓;", 100)));
        using var compressed = new MemoryStream();
        using (var zipper = new GZipStream(compressed, CompressionLevel.Optimal, true)) zipper.Write(input);
        compressed.Position = 0;
        using var unzipper = new GZipStream(compressed, CompressionMode.Decompress);
        using var restored = new MemoryStream();
        unzipper.CopyTo(restored);
        var result = restored.ToArray();
        if (!input.AsSpan().SequenceEqual(result)) throw new InvalidDataException("GZip regression.");
        return Convert.ToHexString(SHA256.HashData(result));
    }

    private static string HashAndHmac()
    {
        var input = Encoding.UTF8.GetBytes("fixture-hash-input-v1");
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes("fixture-public-test-key-v1"));
        return Convert.ToHexString(SHA256.HashData(input)) + ":" + Convert.ToHexString(hmac.ComputeHash(input));
    }

    private static string AesRoundTrip()
    {
        var key = SHA256.HashData(Encoding.UTF8.GetBytes("public-test-data-not-a-secret"));
        byte[] nonce = new byte[12]; // One-off local test only; never use fixed nonces in production encryption.
        byte[] input = Encoding.UTF8.GetBytes("fixture-only encrypted round trip");
        byte[] cipher = new byte[input.Length], decrypted = new byte[input.Length], tag = new byte[16];
        using var aes = new AesGcm(key, 16);
        aes.Encrypt(nonce, input, cipher, tag);
        aes.Decrypt(nonce, cipher, tag, decrypted);
        if (!input.AsSpan().SequenceEqual(decrypted)) throw new CryptographicException("AES regression.");
        return Convert.ToHexString(SHA256.HashData(decrypted));
    }

    private interface ITransformer<T> { T Apply(T value); }
    private sealed class Square : ITransformer<int> { public int Apply(int value) => checked(value * value); }
    private static T Transform<T>(ITransformer<T> operation, T value) => operation.Apply(value);
    private static string Generics() => string.Join(",", new[] { 3, 5, 8 }.Select(x => Transform(new Square(), x)));

    public static class ReflectionTarget { public static string Apply(string text) => text.Trim().ToUpperInvariant() + "|REFLECT"; }
    private static string ReflectionTest()
    {
        var method = typeof(ReflectionTarget).GetMethod("Apply", BindingFlags.Static | BindingFlags.Public)
            ?? throw new MissingMethodException("ReflectionTarget.Apply");
        return (string)(method.Invoke(null, new object[] { " smoke-test " }) ?? throw new Exception("Null reflection result."));
    }

    private static string ResourceTest()
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("CompatibilityFixture.Resources.sample.txt")
            ?? throw new MissingManifestResourceException("Resource is missing.");
        using var reader = new StreamReader(stream, Encoding.UTF8);
        var result = reader.ReadToEnd().Replace("\r\n", "\n", StringComparison.Ordinal);
        if (!result.StartsWith("ADVANCED_EXE_PROTECTOR_TEST_RESOURCE_V1", StringComparison.Ordinal))
            throw new InvalidDataException("Resource changed.");
        return result;
    }

    private static string Exceptions()
    {
        bool finallyRan = false;
        string? caught = null;
        try { throw new ArgumentOutOfRangeException("fixture", "expected"); }
        catch (ArgumentException ex) when (ex.ParamName == "fixture") { caught = "caught:" + ex.ParamName; }
        finally { finallyRan = true; }
        if (!finallyRan || caught is null) throw new InvalidOperationException("Exception behavior changed.");
        return caught;
    }

    private static string FileIo()
    {
        string folder = Path.Combine(Path.GetTempPath(), "AdvancedEXEFixture-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        try
        {
            var file = Path.Combine(folder, "sample.txt");
            File.WriteAllText(file, "temporary benign fixture content ✓", Encoding.UTF8);
            string result = File.ReadAllText(file, Encoding.UTF8);
            if (result != "temporary benign fixture content ✓") throw new IOException("File data changed.");
            return result;
        }
        finally { Directory.Delete(folder, true); }
    }

    private static async Task<string> AsyncWork()
    {
        var values = new ConcurrentDictionary<int, int>();
        await Task.WhenAll(Enumerable.Range(1, 16).Select(async i =>
        {
            await Task.Yield();
            values[i] = i * (i + 1);
        }));
        if (values.Count != 16) throw new Exception("Concurrency regression.");
        return string.Join(",", values.OrderBy(x => x.Key).Select(x => x.Value));
    }

    [DllImport("kernel32.dll", ExactSpelling = true)]
    private static extern ulong GetTickCount64();
    private static string Interop()
    {
        if (!OperatingSystem.IsWindows() || GetTickCount64() == 0)
            throw new PlatformNotSupportedException("Windows P/Invoke failed.");
        return "windows-interop-success";
    }

    public sealed record CaseResult(string Id, bool Passed, string Fingerprint, string? Error);
    public sealed record Report(int SchemaVersion, string FixtureVersion, DateTimeOffset CreatedUtc,
        bool Passed, string OverallFingerprint, List<CaseResult> Tests, string? Error, bool? BaselineMatched);
}
