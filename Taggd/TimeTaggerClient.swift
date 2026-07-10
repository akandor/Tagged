//
//  TimeTaggerClient.swift
//  Taggd
//
//  Thin client for a self-hosted TimeTagger backend.
//  https://github.com/almarklein/timetagger
//
//  Auth: the API token is sent in the `authtoken` HTTP header.
//  All endpoints live under <serverURL>/api/v2/ (enter the install root
//  as the server URL — for a subpath install use e.g. https://host/timetagger).
//

import Foundation

struct TimeTaggerClient {
    let serverURL: String
    let token: String

    /// Builds a client from the saved Server URL + API token, or nil if unconfigured.
    static func fromStoredSettings() -> TimeTaggerClient? {
        let defaults = UserDefaults.standard
        let url = defaults.string(forKey: "serverURL")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let token = defaults.string(forKey: "apiToken")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !url.isEmpty, !token.isEmpty else { return nil }
        return TimeTaggerClient(serverURL: url, token: token)
    }

    enum ConnectionResult: Equatable {
        case success(serverTime: Double)
        case unauthorized
        case badURL
        case failure(String)
    }

    /// Builds `<server>/api/v2/<endpoint>`, tolerating a trailing slash on the base.
    func apiURL(_ endpoint: String) -> URL? {
        var base = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + "/api/v2/" + endpoint)
    }

    // MARK: - Records

    /// A fresh, compact alphanumeric record key (TimeTagger keys are short strings).
    static func generateKey() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<10).map { _ in alphabet.randomElement()! })
    }

    /// A TimeTagger record. A *running* record has `t1 == t2`; a finished one has `t2 > t1`.
    /// Tags are encoded inline in `ds` as `#tag` tokens.
    struct Record: Codable {
        let key: String
        let t1: Int
        let t2: Int
        let mt: Int
        let ds: String
    }

    enum PushResult: Equatable {
        case success
        case unauthorized
        case rejected(String)
        case badURL
        case failure(String)
    }

    enum RecordsResult {
        case success([Record])
        case unauthorized
        case badURL
        case failure(String)
    }

    /// Fetches records overlapping the `[start, end]` unix-second range. The server
    /// replies with `{"records": [...]}`; deleted records (ds prefixed "HIDDEN") are
    /// dropped so the caller only sees live entries.
    func fetchRecords(from start: Int, to end: Int) async -> RecordsResult {
        guard let url = apiURL("records?timerange=\(start)-\(end)") else { return .badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "authtoken")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure("No response from server")
            }
            switch http.statusCode {
            case 200:
                struct Envelope: Decodable { let records: [Record] }
                let decoded = try JSONDecoder().decode(Envelope.self, from: data)
                let live = decoded.records.filter { !$0.ds.hasPrefix("HIDDEN") }
                return .success(live)
            case 401, 403:
                return .unauthorized
            default:
                return .failure("HTTP \(http.statusCode)")
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// PUTs one or more records. The body is a bare JSON array; the server replies
    /// with `{accepted, failed, errors}`.
    func pushRecords(_ records: [Record]) async -> PushResult {
        guard let url = apiURL("records") else { return .badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(token, forHTTPHeaderField: "authtoken")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        do {
            request.httpBody = try JSONEncoder().encode(records)
        } catch {
            return .failure("Could not encode record")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure("No response from server")
            }
            switch http.statusCode {
            case 200:
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let failed = (object?["failed"] as? [Any]) ?? []
                if failed.isEmpty {
                    return .success
                }
                let errors = (object?["errors"] as? [String]) ?? []
                return .rejected(errors.first ?? "Server rejected the record")
            case 401, 403:
                return .unauthorized
            default:
                return .failure("HTTP \(http.statusCode)")
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// "Deletes" a record. TimeTagger keeps history, so deletion is a re-push of the
    /// same key with its description hidden; the app then filters `HIDDEN` records out.
    func deleteRecord(_ record: Record) async -> PushResult {
        let hidden = Record(
            key: record.key,
            t1: record.t1,
            t2: record.t2,
            mt: Int(Date().timeIntervalSince1970),
            ds: record.ds.hasPrefix("HIDDEN") ? record.ds : "HIDDEN " + record.ds
        )
        return await pushRecords([hidden])
    }

    /// Validates the server URL + token with a minimal authenticated request.
    /// `since=now` returns no records, so the payload stays tiny.
    func testConnection() async -> ConnectionResult {
        let since = Date().timeIntervalSince1970
        guard let url = apiURL("updates?since=\(since)") else { return .badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "authtoken")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure("No response from server")
            }
            switch http.statusCode {
            case 200:
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let serverTime = (object?["server_time"] as? Double) ?? 0
                return .success(serverTime: serverTime)
            case 401, 403:
                return .unauthorized
            default:
                return .failure("HTTP \(http.statusCode)")
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
