using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;

namespace TaggdWin.Services
{
    /// <summary>
    /// Thin client for a self-hosted TimeTagger backend. Faithful port of the
    /// Swift <c>TimeTaggerClient</c>. Auth token is sent in the <c>authtoken</c>
    /// header; endpoints live under &lt;serverURL&gt;/api/v2/.
    /// </summary>
    public sealed class TimeTaggerClient
    {
        public string ServerUrl { get; }
        public string Token { get; }

        // One shared HttpClient for the whole process (recommended pattern).
        private static readonly HttpClient Http = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(15)
        };

        public TimeTaggerClient(string serverUrl, string token)
        {
            ServerUrl = serverUrl ?? "";
            Token = token ?? "";
        }

        public sealed class Record
        {
            [JsonPropertyName("key")] public string Key { get; set; } = "";
            [JsonPropertyName("t1")] public long T1 { get; set; }
            [JsonPropertyName("t2")] public long T2 { get; set; }
            [JsonPropertyName("mt")] public long Mt { get; set; }
            [JsonPropertyName("ds")] public string Ds { get; set; } = "";
        }

        // ---- Result kinds ----

        public enum ResultKind { Success, Unauthorized, BadUrl, Rejected, Failure }

        public readonly struct ConnectionResult
        {
            public ResultKind Kind { get; init; }
            public string Message { get; init; }
            public static ConnectionResult Ok() => new() { Kind = ResultKind.Success, Message = "" };
            public static ConnectionResult Unauthorized() => new() { Kind = ResultKind.Unauthorized, Message = "" };
            public static ConnectionResult BadUrl() => new() { Kind = ResultKind.BadUrl, Message = "" };
            public static ConnectionResult Fail(string m) => new() { Kind = ResultKind.Failure, Message = m };
        }

        public readonly struct PushResult
        {
            public ResultKind Kind { get; init; }
            public string Message { get; init; }
            public static PushResult Ok() => new() { Kind = ResultKind.Success, Message = "" };
            public static PushResult Unauthorized() => new() { Kind = ResultKind.Unauthorized, Message = "" };
            public static PushResult BadUrl() => new() { Kind = ResultKind.BadUrl, Message = "" };
            public static PushResult Reject(string m) => new() { Kind = ResultKind.Rejected, Message = m };
            public static PushResult Fail(string m) => new() { Kind = ResultKind.Failure, Message = m };
        }

        /// <summary>Builds &lt;server&gt;/api/v2/&lt;endpoint&gt;, tolerating a trailing slash.</summary>
        private Uri? ApiUrl(string endpoint)
        {
            var baseUrl = (ServerUrl ?? "").Trim();
            if (string.IsNullOrEmpty(baseUrl)) return null;
            baseUrl = baseUrl.TrimEnd('/');
            return Uri.TryCreate(baseUrl + "/api/v2/" + endpoint, UriKind.Absolute, out var uri) ? uri : null;
        }

        /// <summary>PUTs one or more records; server replies {accepted, failed, errors}.</summary>
        public async Task<PushResult> PushRecordsAsync(IReadOnlyList<Record> records)
        {
            var url = ApiUrl("records");
            if (url == null) return PushResult.BadUrl();

            string body;
            try { body = JsonSerializer.Serialize(records); }
            catch { return PushResult.Fail("Could not encode record"); }

            using var request = new HttpRequestMessage(HttpMethod.Put, url);
            request.Headers.TryAddWithoutValidation("authtoken", Token);
            request.Content = new StringContent(body, Encoding.UTF8, "application/json");

            try
            {
                using var response = await Http.SendAsync(request).ConfigureAwait(false);
                var data = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                switch ((int)response.StatusCode)
                {
                    case 200:
                        try
                        {
                            using var doc = JsonDocument.Parse(data);
                            var root = doc.RootElement;
                            var failedCount = root.TryGetProperty("failed", out var failed) && failed.ValueKind == JsonValueKind.Array
                                ? failed.GetArrayLength() : 0;
                            if (failedCount == 0) return PushResult.Ok();
                            string firstError = "Server rejected the record";
                            if (root.TryGetProperty("errors", out var errs) && errs.ValueKind == JsonValueKind.Array && errs.GetArrayLength() > 0)
                                firstError = errs[0].GetString() ?? firstError;
                            return PushResult.Reject(firstError);
                        }
                        catch { return PushResult.Ok(); }
                    case 401:
                    case 403:
                        return PushResult.Unauthorized();
                    default:
                        return PushResult.Fail($"HTTP {(int)response.StatusCode}");
                }
            }
            catch (Exception ex)
            {
                return PushResult.Fail(ex.Message);
            }
        }

        /// <summary>Validates URL + token with a minimal authenticated request.</summary>
        public async Task<ConnectionResult> TestConnectionAsync()
        {
            double since = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0;
            var url = ApiUrl($"updates?since={since.ToString(System.Globalization.CultureInfo.InvariantCulture)}");
            if (url == null) return ConnectionResult.BadUrl();

            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.TryAddWithoutValidation("authtoken", Token);

            try
            {
                using var response = await Http.SendAsync(request).ConfigureAwait(false);
                switch ((int)response.StatusCode)
                {
                    case 200: return ConnectionResult.Ok();
                    case 401:
                    case 403: return ConnectionResult.Unauthorized();
                    default: return ConnectionResult.Fail($"HTTP {(int)response.StatusCode}");
                }
            }
            catch (Exception ex)
            {
                return ConnectionResult.Fail(ex.Message);
            }
        }

        /// <summary>Short random record key (compact alphanumeric, like TimeTagger keys).</summary>
        public static string GenerateKey()
        {
            const string alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
            var chars = new char[10];
            for (int i = 0; i < chars.Length; i++)
                chars[i] = alphabet[Random.Shared.Next(alphabet.Length)];
            return new string(chars);
        }
    }
}
