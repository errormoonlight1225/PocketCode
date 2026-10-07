import UIKit
import SafariServices

enum Theme {
    static var classic: Bool { UserDefaults.standard.bool(forKey: "classicUI") }
    static var foreground: UIColor { classic ? .black : .white }
    static var background: UIColor { classic ? UIColor(white: 0.95, alpha: 1) : UIColor(red: 0.045, green: 0.065, blue: 0.09, alpha: 1) }
    static var panel: UIColor { classic ? .white : UIColor(red: 0.085, green: 0.11, blue: 0.145, alpha: 1) }
    static var mint: UIColor { classic ? UIColor(red: 0, green: 0.36, blue: 0.72, alpha: 1) : UIColor(red: 0.36, green: 0.91, blue: 0.74, alpha: 1) }
    static var muted: UIColor { classic ? .darkGray : UIColor(red: 0.63, green: 0.69, blue: 0.76, alpha: 1) }
    static func mono(_ size: CGFloat) -> UIFont { UIFont(name: "Menlo-Regular", size: size) ?? UIFont.systemFont(ofSize: size) }
}
@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        rebuildUI(); window?.makeKeyAndVisible()
        return true
    }
    func rebuildUI() {
        UINavigationBar.appearance().barStyle = Theme.classic ? .default : .black
        UINavigationBar.appearance().barTintColor = Theme.background; UINavigationBar.appearance().tintColor = Theme.mint
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: Theme.foreground]
        UITabBar.appearance().barStyle = Theme.classic ? .default : .black
        UITabBar.appearance().barTintColor = Theme.background; UITabBar.appearance().tintColor = Theme.mint
        window?.tintColor = Theme.mint
        if Theme.classic {
            let home = ClassicHomeController(); home.title = "Pocket Code · 经典"
            home.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "设置", style: .plain, target: self, action: #selector(connection))
            window?.rootViewController = UINavigationController(rootViewController: home)
        } else {
            let tabs = UITabBarController()
            let pages: [(UIViewController, String, UITabBarItem.SystemItem)] = [(SpacesController(), "工作区", .featured), (FilesController(), "文件", .bookmarks), (EditorsController(), "编辑器", .more), (TerminalController(), "终端", .history), (GitController(), "Git", .recents)]
            pages[0].0.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "连接", style: .plain, target: self, action: #selector(connection))
            tabs.viewControllers = pages.enumerated().map { i, p in
                p.0.title = p.1; let nav = UINavigationController(rootViewController: p.0)
                nav.tabBarItem = UITabBarItem(tabBarSystemItem: p.2, tag: i); nav.tabBarItem.title = p.1; return nav
            }
            window?.rootViewController = tabs
        }
    }
    @objc func connection() {
        let c = ConnectController(); c.title = "连接与登录"
        c.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: c, action: #selector(ConnectController.finish))
        window?.rootViewController?.present(UINavigationController(rootViewController: c), animated: true)
    }
    func applicationDidEnterBackground(_ application: UIApplication) { try? Pocket.shared.persist() }
}
extension UIViewController {
    func message(_ text: String, title: String = "Pocket Code") {
        let a = UIAlertController(title: title, message: text, preferredStyle: .alert); a.addAction(UIAlertAction(title: "好", style: .default)); present(a, animated: true)
    }
    func prompt(_ title: String, placeholder: String = "", secure: Bool = false, value: String = "", action: @escaping (String) -> Void) {
        let a = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        a.addTextField { f in f.placeholder = placeholder; f.text = value; f.isSecureTextEntry = secure; f.autocapitalizationType = .none; f.autocorrectionType = .no }
        a.addAction(UIAlertAction(title: "取消", style: .cancel)); a.addAction(UIAlertAction(title: "确定", style: .default) { _ in action(a.textFields?.first?.text ?? "") }); present(a, animated: true)
    }
    func confirm(_ title: String, _ text: String, action: @escaping () -> Void) {
        let a = UIAlertController(title: title, message: text, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "取消", style: .cancel)); a.addAction(UIAlertAction(title: "继续", style: .default) { _ in action() }); present(a, animated: true)
    }
}
class ListController: UITableViewController {
    let p = Pocket.shared
    init() { super.init(style: .grouped) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() { super.viewDidLoad(); tableView.backgroundColor = Theme.background; tableView.separatorColor = Theme.panel; tableView.rowHeight = UITableView.automaticDimension; tableView.estimatedRowHeight = 68 }
    func cell(_ text: String, detail: String = "", arrow: Bool = false) -> UITableViewCell {
        let c = UITableViewCell(style: .subtitle, reuseIdentifier: nil); c.backgroundColor = Theme.panel; c.textLabel?.textColor = Theme.foreground; c.textLabel?.font = .systemFont(ofSize: 16, weight: .medium); c.textLabel?.numberOfLines = 0
        c.detailTextLabel?.textColor = Theme.muted; c.detailTextLabel?.numberOfLines = 0; c.detailTextLabel?.font = .systemFont(ofSize: 12); c.textLabel?.text = text; c.detailTextLabel?.text = detail
        c.accessoryType = arrow ? .disclosureIndicator : .none; let bg = UIView(); bg.backgroundColor = Theme.background; c.selectedBackgroundView = bg; return c
    }
    func receive(_ result: Result<JSON, Error>, success: (JSON) -> Void) { do { success(try result.get()) } catch { message(error.localizedDescription) } }
}
final class ConnectController: ListController, SFSafariViewControllerDelegate {
    let login = DeviceLogin()
    var status = "通过 GitHub 官方页面登录。账号密码只输入 GitHub。"
    var code = ""
    weak var safari: SFSafariViewController?
    override func viewDidLoad() {
        super.viewDidLoad(); title = "连接与登录"
        login.update = { [weak self] s in self?.status = s; self?.tableView.reloadData() }
        login.completed = { [weak self] e in
            guard let self = self else { return }
            if let e = e { self.status = e.localizedDescription } else { self.code = ""; self.safari?.dismiss(animated: true) }
            self.tableView.reloadData()
        }
    }
    deinit { login.cancel() }
    @objc func finish() { dismiss(animated: true) }
    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { [5, 3, 2, 2][section] }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { ["GITHUB 账号", "原生工作区", "帮助", "界面风格"][section] }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 3 { return "切换后立即生效并记住选择。账号、工作区和草稿保持共用。两种界面都支持 iOS 12。" }
        if section == 0 { return status }
        if section == 1 { return "支持粘贴 https://名称.github.dev，自动转换为 8765 私有端口。仍需在 Codespace 启动 Pocket Bridge。" }
        return "iOS 12+ · UIKit 原生版 2.1。网页版 IDE 是否支持旧 Safari 由 GitHub 决定。"
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let i = indexPath.row
        if indexPath.section == 3 {
            let c = cell(i == 0 ? "新版 UI" : "经典 UI", detail: i == 0 ? "深色主题 · 底部多标签导航" : "浅色主题 · 分组列表菜单")
            c.accessoryType = Theme.classic == (i == 1) ? .checkmark : .none; return c
        }
        if indexPath.section == 0 {
            return [cell("使用 GitHub 账号登录", detail: "官方设备授权；支持 GitHub 的密码和双重验证", arrow: true), cell("OAuth Client ID", detail: p.clientID.isEmpty ? "首次需配置自己的 OAuth 应用（不是密码）" : p.clientID, arrow: true), cell(code.isEmpty ? "授权码" : "复制授权码：" + code, detail: code.isEmpty ? "点击登录后显示" : "在 GitHub 官方授权页输入此码"), cell("使用已有 Token", detail: p.token.isEmpty ? "备用登录方式" : "已安全保存授权", arrow: true), cell("退出本机登录")][i]
        }
        if indexPath.section == 1 { return [cell("工作区地址", detail: p.address.isEmpty ? "粘贴 .github.dev 地址" : p.address, arrow: true), cell("连接密钥", detail: p.key.isEmpty ? "Pocket Bridge 启动时显示" : "已保存", arrow: true), cell("连接工作区", detail: p.connected ? "已连接" : "使用私有端口连接原生编辑器", arrow: true)][i] }
        return i == 0 ? cell("安装和登录说明", arrow: true) : cell("在 Safari 打开工作区", detail: "可选入口；原生编辑不依赖网页 IDE", arrow: true)
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 3 {
            let classic = indexPath.row == 1
            guard classic != Theme.classic else { return }
            guard code.isEmpty else { message("请先完成正在进行的 GitHub 授权，再切换界面。"); return }
            do { try p.persist() } catch { message(error.localizedDescription); return }
            UserDefaults.standard.set(classic, forKey: "classicUI")
            let app = UIApplication.shared.delegate as? AppDelegate
            dismiss(animated: false) { app?.rebuildUI() }
            return
        }
        if indexPath.section == 0 {
            switch indexPath.row {
            case 0:
                guard !p.clientID.isEmpty else { message("请先配置 OAuth Client ID。它来自你在 GitHub Developer settings 注册的 OAuth App，需启用 Device Flow。也可以使用已有 Token。"); return }
                status = "正在申请授权码…"; tableView.reloadData()
                login.begin(clientID: p.clientID) { [weak self] c in
                    guard let self = self else { return }; self.code = c; self.status = "等待你在 GitHub 完成授权"; self.tableView.reloadData()
                    self.confirm("GitHub 授权码：" + c, "下一步复制此码并打开 GitHub 官方登录页。登录后粘贴授权码，确认 Pocket Code 权限。") {
                        UIPasteboard.general.string = c
                        let s = SFSafariViewController(url: URL(string: "https://github.com/login/device")!); s.delegate = self; self.safari = s; self.present(s, animated: true)
                    }
                }
            case 1: prompt("OAuth Client ID", value: p.clientID) { self.login.cancel(); self.p.clientID = $0; self.tableView.reloadData() }
            case 2: if !code.isEmpty { UIPasteboard.general.string = code; message("授权码已复制") }
            case 3: prompt("GitHub Token", placeholder: "需要 codespace 权限", secure: true) { value in
                self.login.cancel()
                do { try self.p.usePAT(value); self.p.request("user", github: true) { r in self.receive(r) { self.status = "已登录 @" + ($0["login"] as? String ?? "GitHub"); self.tableView.reloadData() } } } catch { self.message(error.localizedDescription) }
            }
            default: confirm("退出登录", "清除本机 GitHub 授权。云端授权可在 GitHub 设置中撤销。") {
                self.login.cancel(); do { try self.p.usePAT(""); self.p.connected = false; self.p.terminalID = nil; self.p.terminalGeneration += 1; self.code = ""; self.status = "已退出"; self.tableView.reloadData() } catch { self.message(error.localizedDescription) }
            }
            }
        } else if indexPath.section == 1 {
            switch indexPath.row {
            case 0: prompt("工作区地址", placeholder: "https://名称.github.dev", value: p.address) { value in do { try self.p.saveSettings(address: value, key: self.p.key); self.tableView.reloadData() } catch { self.message(error.localizedDescription) } }
            case 1: prompt("连接密钥", secure: true) { value in do { try self.p.saveSettings(address: self.p.address, key: value); self.tableView.reloadData() } catch { self.message(error.localizedDescription) } }
            default:
                p.connected = false
                p.request("health") { r in self.receive(r) { j in
                    guard j["version"] as? Int == 2 else { self.message("请运行 Pocket Bridge v2"); return }
                    self.p.connected = true; self.tableView.reloadData(); self.message("已连接：" + (j["name"] as? String ?? "工作区"))
                } }
            }
        } else {
            if indexPath.row == 0 { present(SFSafariViewController(url: URL(string: "https://github.com/errormoonlight1225/PocketCode#readme")!), animated: true) }
            else if let host = URL(string: p.address)?.host, let range = host.range(of: "-[0-9]+\\.app\\.github\\.dev$", options: .regularExpression), let url = URL(string: "https://" + host[..<range.lowerBound] + ".github.dev") { UIApplication.shared.open(url) }
            else { message("请先填写工作区地址") }
        }
    }
}
final class SpacesController: ListController {
    var spaces: [JSON] = []
    var loading = false
    override func viewDidLoad() { super.viewDidLoad(); navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refresh)); refreshControl = UIRefreshControl(); refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged) }
    @objc func refresh() { guard !loading else { return }; loading = true; load(page: 1, previous: []) }
    func load(page: Int, previous: [JSON]) {
        p.request("user/codespaces", query: ["per_page": "100", "page": "\(page)"], github: true) { r in
            do { let j = try r.get(); let rows = j["codespaces"] as? [JSON] ?? []; let all = previous + rows
                if rows.count == 100 && page < 20 { self.load(page: page + 1, previous: all); return }
                self.spaces = all; self.tableView.reloadData()
            } catch { self.message(error.localizedDescription) }
            self.loading = false; self.refreshControl?.endRefreshing()
        }
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { max(1, spaces.count) }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard !spaces.isEmpty else { return cell("你的云端工作区", detail: "先点左上角「连接」登录，再刷新。") }
        let s = spaces[indexPath.row]; return cell(s["display_name"] as? String ?? s["name"] as? String ?? "Codespace", detail: ((s["repository"] as? JSON)?["full_name"] as? String ?? "") + " · " + (s["state"] as? String ?? ""), arrow: true)
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true); guard !spaces.isEmpty, let name = spaces[indexPath.row]["name"] as? String else { return }
        let a = UIAlertController(title: name, message: "选择工作区操作", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "使用此工作区", style: .default) { _ in do { let next = try Pocket.bridgeAddress("https://\(name).github.dev"); try self.p.saveSettings(address: next, key: next == self.p.address ? self.p.key : ""); self.message("地址已设置。请在「连接」填写该工作区的 Bridge 密钥，然后连接。") } catch { self.message(error.localizedDescription) } })
        a.addAction(UIAlertAction(title: "启动", style: .default) { _ in self.confirm("启动 Codespace", "运行会消耗你的 GitHub Codespaces 配额。") { self.p.request("user/codespaces/\(name)/start", body: [:], github: true) { r in self.receive(r) { _ in self.refresh() } } } })
        a.addAction(UIAlertAction(title: "停止", style: .destructive) { _ in self.confirm("停止 Codespace", "将中断此工作区的运行任务。") { self.p.request("user/codespaces/\(name)/stop", body: [:], github: true) { r in self.receive(r) { _ in self.p.connected = false; self.refresh() } } } })
        a.addAction(UIAlertAction(title: "取消", style: .cancel)); present(a, animated: true)
    }
}
final class FilesController: ListController {
    var path = ""
    var entries: [JSON] = []
    override func viewDidLoad() { super.viewDidLoad(); navigationItem.rightBarButtonItems = [UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refresh)), UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(create))] }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); if p.connected { refresh() } }
    @objc func refresh() { p.request("files", query: ["path": path]) { r in self.receive(r) { self.entries = $0["entries"] as? [JSON] ?? []; self.tableView.reloadData() } } }
    @objc func create() { prompt("创建文件或文件夹", placeholder: "文件夹名称以 / 结尾") { name in
        guard !name.isEmpty else { return }; let directory = name.hasSuffix("/"); let leaf = directory ? String(name.dropLast()) : name
        self.p.request("create", body: ["path": self.path.isEmpty ? leaf : self.path + "/" + leaf, "directory": directory]) { r in self.receive(r) { _ in self.refresh() } }
    } }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { entries.count + (path.isEmpty ? 0 : 1) }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { !p.connected ? "先在工作区 → 连接，登录并连接 Pocket Bridge。" : path.isEmpty ? "/ · 选择文件开始编辑" : path }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if !path.isEmpty && indexPath.row == 0 { return cell("↑ 上一级", arrow: true) }
        let e = entries[indexPath.row - (path.isEmpty ? 0 : 1)]; return cell((e["directory"] as? Bool == true ? "▸ " : "") + (e["name"] as? String ?? ""), detail: e["directory"] as? Bool == true ? "文件夹" : "UTF-8 文本", arrow: true)
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if !path.isEmpty && indexPath.row == 0 { path = (path as NSString).deletingLastPathComponent; refresh(); return }
        let e = entries[indexPath.row - (path.isEmpty ? 0 : 1)]; guard let selected = e["path"] as? String else { return }
        if e["directory"] as? Bool == true { path = selected; refresh(); return }
        if p.documents.contains(where: { $0.id == selected }) { openEditor(selected); return }
        p.request("file", query: ["path": selected]) { r in self.receive(r) { j in
            guard !self.p.documents.contains(where: { $0.id == selected }) else { self.openEditor(selected); return }
            let text = j["content"] as? String ?? ""; self.p.documents.append(Document(id: selected, text: text, saved: text, revision: j["revision"] as? String ?? ""))
            do { try self.p.persist() } catch { self.message(error.localizedDescription); return }; self.openEditor(selected)
        } }
    }
    func openEditor(_ id: String) { navigationController?.pushViewController(EditorController(id: id), animated: true) }
}
final class EditorsController: ListController {
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); tableView.reloadData() }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { p.documents.count }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { "已打开的文件和本地草稿。左滑可关闭；有未保存修改会先确认。" }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { let d = p.documents[indexPath.row]; return cell((d.dirty ? "● " : "") + (d.id as NSString).lastPathComponent, detail: d.id, arrow: true) }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { navigationController?.pushViewController(EditorController(id: p.documents[indexPath.row].id), animated: true) }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        let d = p.documents[indexPath.row]
        let close = { self.p.documents.removeAll { $0.id == d.id }; do { try self.p.persist() } catch { self.message(error.localizedDescription) }; self.tableView.reloadData() }
        if d.dirty { confirm("放弃未保存修改？", d.id, action: close) } else { close() }
    }
}
final class GitController: UIViewController {
    let p = Pocket.shared
    let text = UITextView()
    var branches: [String] = []
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = Theme.background; text.backgroundColor = Theme.background; text.textColor = Theme.foreground; text.font = Theme.mono(13); text.isEditable = false; text.text = "连接工作区后刷新 Git 状态"; text.frame = view.bounds; text.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(text)
        navigationItem.rightBarButtonItems = [UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refresh)), UIBarButtonItem(title: "操作", style: .plain, target: self, action: #selector(actions))]
    }
    @objc func refresh() { p.request("git") { r in
        do { let j = try r.get(); self.branches = j["branches"] as? [String] ?? []; self.text.text = "分支  \(j["branch"] as? String ?? "")\n\n状态\n\(j["status"] as? String ?? "")\n\n差异\n\(j["diff"] as? String ?? "")" } catch { self.message(error.localizedDescription) }
    } }
    func run(_ action: String, message: String = "", branch: String = "") { p.request("git", body: ["action": action, "message": message, "branch": branch]) { r in do { let j = try r.get(); self.refresh(); self.message(j["output"] as? String ?? "完成") } catch { self.message(error.localizedDescription) } } }
    @objc func actions() {
        let a = UIAlertController(title: "Git", message: "先保存编辑器中的修改，再提交。", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "提交全部更改", style: .default) { _ in self.prompt("提交说明", placeholder: "会暂存并提交工作区全部更改") { self.run("commit", message: $0) } })
        a.addAction(UIAlertAction(title: "推送", style: .default) { _ in self.confirm("推送到远端", "把当前分支的本地提交发送到已配置的远端仓库。") { self.run("push") } })
        a.addAction(UIAlertAction(title: "切换分支", style: .default) { _ in
            guard self.p.documents.isEmpty else { self.message("切换分支前请保存并关闭所有文件。"); return }
            let b = UIAlertController(title: "本地分支", message: "先刷新以获取最新分支列表", preferredStyle: .alert)
            for branch in self.branches { b.addAction(UIAlertAction(title: branch, style: .default) { _ in self.run("switch", branch: branch) }) }; b.addAction(UIAlertAction(title: "取消", style: .cancel)); self.present(b, animated: true)
        }); a.addAction(UIAlertAction(title: "取消", style: .cancel)); present(a, animated: true)
    }
}

final class ClassicHomeController: ListController {
    let labels = ["工作区", "文件浏览", "已打开的文档", "终端", "Git"]
    let details = ["管理 GitHub Codespaces", "浏览目录、新建和编辑文件", "继续编辑本地草稿", "原生 Shell 与快捷键", "差异、提交、推送与分支"]
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { labels.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { "经典工作台" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { "设置 → 界面风格，可随时切换新版 UI。" }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { cell(labels[indexPath.row], detail: details[indexPath.row], arrow: true) }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let pages: [UIViewController] = [SpacesController(), FilesController(), EditorsController(), TerminalController(), GitController()]
        let page = pages[indexPath.row]; page.title = labels[indexPath.row]; navigationController?.pushViewController(page, animated: true)
    }
}
