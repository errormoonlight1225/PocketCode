import Foundation
import Security

typealias JSON = [String: Any]
typealias Reply = (Result<JSON, Error>) -> Void
struct PocketError: LocalizedError { let message: String; var errorDescription: String? { message } }
enum Vault {
    static func read(_ key: String) -> String {
        let q: JSON = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.codespacepocket.native", kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func write(_ key: String, _ value: String) throws {
        let q: JSON = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.codespacepocket.native", kSecAttrAccount as String: key]
        if value.isEmpty { SecItemDelete(q as CFDictionary); return }
        let data = Data(value.utf8)
        let update = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw PocketError(message: "无法更新安全存储") }
        var item = q; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw PocketError(message: "无法保存登录信息") }
    }
}
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct Document: Codable { var id: String; var text: String; var saved: String; var revision: String; var dirty: Bool { text != saved } }
final class Pocket {
    static let shared = Pocket()
    var token = Vault.read("github")
    var key = Vault.read("bridge")
    var address = UserDefaults.standard.string(forKey: "bridgeURL") ?? ""
    var clientID: String {
        get { UserDefaults.standard.string(forKey: "oauthClientID") ?? "Ov23li2cGH8F49C6Bth5" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "oauthClientID") }
    }
    var connected = false
    var documents: [Document] = []
    var terminalID: String?
    var terminalGeneration = 0
    let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
    private var refreshing = false
    private var refreshWaiters: [(Error?) -> Void] = []
    private let draftURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("drafts.json")
    init() {
        if UserDefaults.standard.string(forKey: "draftWorkspace") == address, let data = try? Data(contentsOf: draftURL), let docs = try? JSONDecoder().decode([Document].self, from: data) { documents = docs }
    }
    func persist() throws {
        try FileManager.default.createDirectory(at: draftURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(documents).write(to: draftURL, options: [.atomic, .completeFileProtection])
        UserDefaults.standard.set(address, forKey: "draftWorkspace")
    }
    // Only exact Codespaces host shapes are accepted; never send credentials to arbitrary URLs.
    static func bridgeAddress(_ input: String) throws -> String {
        guard let u = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)), u.scheme == "https", let host = u.host?.lowercased(), u.user == nil, u.password == nil, u.port == nil, u.query == nil, u.fragment == nil, u.path.isEmpty || u.path == "/" else { throw PocketError(message: "请输入完整的 https://名称.github.dev 或 https://名称-8765.app.github.dev 地址") }
        if host.hasSuffix(".app.github.dev") {
            let label = String(host.dropLast(".app.github.dev".count))
            guard !label.isEmpty, !label.contains("."), label.range(of: "^[a-z0-9-]+-[0-9]+$", options: .regularExpression) != nil else { throw PocketError(message: "无效的端口转发地址") }
            return "https://" + host
        }
        guard host.hasSuffix(".github.dev"), host != "app.github.dev" else { throw PocketError(message: "只支持 GitHub Codespaces 地址") }
        let name = String(host.dropLast(".github.dev".count))
        guard name.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil else { throw PocketError(message: "无效的 Codespace 名称") }
        return "https://\(name)-8765.app.github.dev"
    }
    func saveSettings(address input: String, key newKey: String) throws {
        let next = try Self.bridgeAddress(input)
        if next != address && !documents.isEmpty { throw PocketError(message: "切换工作区前请保存并关闭所有文件，避免草稿混入其他项目") }
        if next != address || newKey != key { connected = false; terminalID = nil; terminalGeneration += 1 }
        try Vault.write("bridge", newKey.trimmingCharacters(in: .whitespacesAndNewlines))
        key = newKey.trimmingCharacters(in: .whitespacesAndNewlines); address = next
        UserDefaults.standard.set(address, forKey: "bridgeURL")
    }
    @discardableResult func send(_ req: URLRequest, completion: @escaping Reply) -> URLSessionDataTask {
        let task = session.dataTask(with: req) { data, response, error in
            var result: Result<JSON, Error>
            if let error = error { result = .failure(error) }
            else if let http = response as? HTTPURLResponse {
                let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? JSON
                if !(200..<300).contains(http.statusCode) {
                    result = .failure(PocketError(message: (j?["message"] as? String) ?? (j?["error_description"] as? String) ?? (j?["error"] as? String) ?? "HTTP \(http.statusCode)：请检查登录授权、连接密钥及私有端口转发"))
                } else if let j = j { result = .success(j) }
                else if data?.isEmpty != false { result = .success([:]) }
                else { result = .failure(PocketError(message: "服务器未返回 JSON；请检查地址是否为 Pocket Bridge 端口")) }
            } else { result = .failure(PocketError(message: "没有服务器响应")) }
            DispatchQueue.main.async { completion(result) }
        }; task.resume(); return task
    }
    func oauth(_ path: String, values: [String: String], completion: @escaping Reply) {
        var req = URLRequest(url: URL(string: "https://github.com/" + path)!); req.httpMethod = "POST"; req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Accept"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: values); send(req, completion: completion)
    }
    func storeOAuth(_ j: JSON) throws {
        guard let value = j["access_token"] as? String, !value.isEmpty else { throw PocketError(message: "GitHub 未返回访问授权") }
        try Vault.write("github", value); try Vault.write("refresh", j["refresh_token"] as? String ?? "")
        token = value
        let expiry = (j["expires_in"] as? Double).map { Date().timeIntervalSince1970 + $0 } ?? 0
        UserDefaults.standard.set(expiry, forKey: "tokenExpiry")
    }
    func usePAT(_ value: String) throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try Vault.write("github", value); try Vault.write("refresh", ""); token = value
        UserDefaults.standard.removeObject(forKey: "tokenExpiry")
    }
    func validToken(_ completion: @escaping (Error?) -> Void) {
        let expiry = UserDefaults.standard.double(forKey: "tokenExpiry")
        guard expiry > 0 && expiry < Date().timeIntervalSince1970 + 120 else { completion(nil); return }
        refreshWaiters.append(completion); guard !refreshing else { return }; refreshing = true
        let refresh = Vault.read("refresh")
        oauth("login/oauth/access_token", values: ["client_id": clientID, "grant_type": "refresh_token", "refresh_token": refresh]) { result in
            var error: Error?
            do { let j = try result.get(); if let e = j["error"] as? String { throw PocketError(message: "登录已过期，请重新授权：\(e)") }; try self.storeOAuth(j) } catch let e { error = e }
            self.refreshing = false; let waiters = self.refreshWaiters; self.refreshWaiters = []; waiters.forEach { $0(error) }
        }
    }
    func request(_ path: String, query: [String: String] = [:], body: JSON? = nil, github: Bool = false, completion: @escaping Reply) {
        validToken { error in
            if let error = error { completion(.failure(error)); return }
            do {
                let base = github ? "https://api.github.com" : (try Self.bridgeAddress(self.address))
                var c = URLComponents(string: base + "/" + path)!
                c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
                var req = URLRequest(url: c.url!); req.timeoutInterval = 60; req.setValue("application/json", forHTTPHeaderField: "Accept")
                if github {
                    guard !self.token.isEmpty else { throw PocketError(message: "请先到连接页登录 GitHub") }
                    req.setValue("Bearer " + self.token, forHTTPHeaderField: "Authorization"); req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                } else { req.setValue(self.token, forHTTPHeaderField: "X-Github-Token"); req.setValue(self.key, forHTTPHeaderField: "X-Pocket-Key") }
                if let body = body { req.httpMethod = "POST"; req.httpBody = try JSONSerialization.data(withJSONObject: body); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
                self.send(req, completion: completion)
            } catch { completion(.failure(error)) }
        }
    }
}

// Device grant has no embedded client secret. Codes and tokens stay off logs.
final class DeviceLogin {
    let p = Pocket.shared
    var generation = 0
    var deadline = Date()
    var interval: Double = 5
    var device = ""
    var client = ""
    var update: ((String) -> Void)?
    var completed: ((Error?) -> Void)?
    func cancel() { generation += 1; device = "" }
    func begin(clientID: String, code: @escaping (String) -> Void) {
        cancel(); let g = generation; client = clientID
        p.oauth("login/device/code", values: ["client_id": client, "scope": "codespace"]) { result in
            guard g == self.generation else { return }
            do {
                let j = try result.get()
                guard let d = j["device_code"] as? String, let u = j["user_code"] as? String, j["verification_uri"] as? String == "https://github.com/login/device" else { throw PocketError(message: (j["error_description"] as? String) ?? "请检查 OAuth Client ID，且启用 Device Flow") }
                self.device = d; self.interval = max(5, j["interval"] as? Double ?? 5); self.deadline = Date().addingTimeInterval(j["expires_in"] as? Double ?? 900)
                code(u); self.schedule(g)
            } catch { self.completed?(error) }
        }
    }
    func schedule(_ g: Int) { DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in self?.poll(g) } }
    func poll(_ g: Int) {
        guard g == generation else { return }
        guard Date() < deadline else { completed?(PocketError(message: "授权码已过期，请重新登录")); cancel(); return }
        p.oauth("login/oauth/access_token", values: ["client_id": client, "device_code": device, "grant_type": "urn:ietf:params:oauth:grant-type:device_code"]) { result in
            guard g == self.generation else { return }
            do {
                let j = try result.get()
                if let e = j["error"] as? String {
                    if e == "authorization_pending" { self.schedule(g); return }
                    if e == "slow_down" { self.interval += 5; self.schedule(g); return }
                    throw PocketError(message: (j["error_description"] as? String) ?? e)
                }
                try self.p.storeOAuth(j); self.p.clientID = self.client
                self.p.request("user", github: true) { r in
                    guard g == self.generation else { return }
                    do { let user = try r.get(); self.update?("已登录 @" + (user["login"] as? String ?? "GitHub")); self.completed?(nil) } catch { self.completed?(error) }
                    self.cancel()
                }
            } catch { self.completed?(error); self.cancel() }
        }
    }
}
