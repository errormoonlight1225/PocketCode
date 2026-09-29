import UIKit

final class TerminalText: UITextView {
    var output: ((Data) -> Void)?
    override func insertText(_ text: String) { output?(Data(text.replacingOccurrences(of: "\n", with: "\r").utf8)) }
    override func deleteBackward() { output?(Data([127])) }
    override var keyCommands: [UIKeyCommand]? {
        let items: [(String, UIKeyModifierFlags)] = [(UIKeyCommand.inputUpArrow, []), (UIKeyCommand.inputDownArrow, []), (UIKeyCommand.inputLeftArrow, []), (UIKeyCommand.inputRightArrow, []), (UIKeyCommand.inputEscape, []), ("c", .control), ("d", .control), ("a", .control), ("e", .control), ("l", .control)]
        return items.map { UIKeyCommand(input: $0.0, modifierFlags: $0.1, action: #selector(key(_:))) }
    }
    @objc func key(_ command: UIKeyCommand) {
        guard let key = command.input else { return }
        let arrows = [UIKeyCommand.inputUpArrow: "\u{1b}[A", UIKeyCommand.inputDownArrow: "\u{1b}[B", UIKeyCommand.inputRightArrow: "\u{1b}[C", UIKeyCommand.inputLeftArrow: "\u{1b}[D", UIKeyCommand.inputEscape: "\u{1b}"]
        if command.modifierFlags.contains(.control), let byte = key.utf8.first { output?(Data([byte & 31])) } else if let value = arrows[key] { output?(Data(value.utf8)) }
    }
}
final class TerminalController: UIViewController {
    let p = Pocket.shared
    let screen = ANSIScreen()
    let terminal = TerminalText()
    let status = UILabel()
    var bottom: NSLayoutConstraint!
    var active = false, loading = false, sending = false, creating = false
    var generation = 0, offset = 0, workspaceGeneration = -1
    var queued: [Data] = []
    var keys: [String] = []
    var failures = 0
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = Theme.background
        terminal.backgroundColor = .black; terminal.textColor = Theme.mint; terminal.font = Theme.mono(12); terminal.autocorrectionType = .no; terminal.autocapitalizationType = .none; terminal.smartQuotesType = .no; terminal.smartDashesType = .no; terminal.keyboardAppearance = .dark
        terminal.textContainer.widthTracksTextView = false; terminal.textContainer.size = CGSize(width: 10000, height: CGFloat.greatestFiniteMagnitude); terminal.textContainerInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        terminal.output = { [weak self] data in self?.queue(data) }; screen.response = terminal.output
        status.font = Theme.mono(11); status.textColor = Theme.muted; status.numberOfLines = 2; status.text = "连接工作区后点击键盘"
        for v in [status, terminal] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        bottom = terminal.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        NSLayoutConstraint.activate([status.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8), status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8), status.heightAnchor.constraint(equalToConstant: 36), terminal.topAnchor.constraint(equalTo: status.bottomAnchor), terminal.leadingAnchor.constraint(equalTo: view.leadingAnchor), terminal.trailingAnchor.constraint(equalTo: view.trailingAnchor), bottom])
        navigationItem.rightBarButtonItems = [UIBarButtonItem(title: "键盘", style: .plain, target: self, action: #selector(toggleKeyboard)), UIBarButtonItem(title: "新会话", style: .plain, target: self, action: #selector(restart))]
        let bar = UIToolbar(); bar.barStyle = .black; bar.tintColor = Theme.mint; bar.sizeToFit()
        let pairs = [("Esc", "\u{1b}"), ("Tab", "\t"), ("^C", "\u{3}"), ("^D", "\u{4}"), ("↑", "\u{1b}[A"), ("↓", "\u{1b}[B"), ("←", "\u{1b}[D"), ("→", "\u{1b}[C")]
        keys = pairs.map { $0.1 }; bar.items = pairs.enumerated().map { i, item in let b = UIBarButtonItem(title: item.0, style: .plain, target: self, action: #selector(special(_:))); b.tag = i; return b }; terminal.inputAccessoryView = bar
        NotificationCenter.default.addObserver(self, selector: #selector(keyboard(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pause), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); resume() }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); pause() }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); resize() }
    func resize() {
        let width = max(10, Int((terminal.bounds.width - 18) / ("M" as NSString).size(withAttributes: [.font: Theme.mono(12)]).width))
        let height = max(3, Int((terminal.bounds.height - 8) / Theme.mono(12).lineHeight))
        guard width != screen.cols || height != screen.rows else { return }; screen.resize(width, height)
        if active, let id = p.terminalID { p.request("terminal/resize", body: ["id": id, "cols": width, "rows": height]) { _ in } }
    }
    @objc func keyboard(_ n: Notification) { guard let f = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }; bottom.constant = -max(0, view.bounds.intersection(view.convert(f, from: nil)).height - view.safeAreaInsets.bottom); view.layoutIfNeeded() }
    @objc func special(_ b: UIBarButtonItem) { queue(Data(keys[b.tag].utf8)) }
    @objc func toggleKeyboard() { if terminal.isFirstResponder { terminal.resignFirstResponder() } else { terminal.becomeFirstResponder(); resume() } }
    @objc func pause() { active = false; generation += 1; loading = false }
    @objc func resume() {
        guard viewIfLoaded?.window != nil, p.connected, !active else { return }
        if workspaceGeneration != p.terminalGeneration { screen.reset(); terminal.text = ""; offset = 0; queued = []; workspaceGeneration = p.terminalGeneration }
        active = true; generation += 1; let g = generation; failures = 0
        if p.terminalID == nil {
            guard !creating else { return }; creating = true
            status.text = "正在创建原生 PTY…"
            let wg = p.terminalGeneration
            p.request("terminal/new", body: [:]) { r in
                self.creating = false
                do {
                    let j = try r.get(); guard let id = j["id"] as? String else { throw PocketError(message: "没有收到终端 ID") }
                    guard wg == self.p.terminalGeneration else { return }
                    // Retain a created shell even if the view was temporarily hidden.
                    self.p.terminalID = id; self.offset = 0
                    self.p.request("terminal/resize", body: ["id": id, "cols": self.screen.cols, "rows": self.screen.rows]) { _ in }
                    if self.active { self.poll(self.generation) }
                } catch { if self.generation == g { self.status.text = error.localizedDescription; self.active = false } }
            }
        } else { poll(g) }
        resize()
    }
    func poll(_ g: Int) {
        guard active, g == generation, let id = p.terminalID, !loading else { return }; loading = true
        p.request("terminal/read", query: ["id": id, "offset": "\(offset)"]) { r in
            guard self.active, self.generation == g else { return }; self.loading = false
            do {
                let j = try r.get()
                guard self.workspaceGeneration == self.p.terminalGeneration else { self.pause(); return }
                if let s = j["data"] as? String, let data = Data(base64Encoded: s), !data.isEmpty {
                    let atBottom = self.terminal.contentOffset.y + self.terminal.bounds.height >= self.terminal.contentSize.height - 40
                    self.screen.feed(data); self.terminal.text = self.screen.text
                    if atBottom { self.terminal.scrollRangeToVisible(NSRange(location: max(0, self.terminal.text.utf16.count - 1), length: 0)) }
                }
                self.offset = j["offset"] as? Int ?? self.offset; self.failures = 0
                self.status.text = "PTY · \(self.screen.cols)×\(self.screen.rows) · 基础 ANSI"
                if j["truncated"] as? Bool == true { self.status.text = "旧输出超出服务缓存；显示最近内容" }
                if j["closed"] as? Bool == true { self.status.text = "Shell 已退出，请新建会话"; self.active = false; return }
            } catch { self.failures += 1; self.status.text = error.localizedDescription; if self.failures >= 5 { self.active = false; return } }
            DispatchQueue.main.asyncAfter(deadline: .now() + (self.failures == 0 ? 0.2 : 2)) { [weak self] in self?.poll(g) }
        }
    }
    func queue(_ data: Data) { guard p.connected, p.terminalID != nil, workspaceGeneration == p.terminalGeneration else { return }; if queued.reduce(0, { $0 + $1.count }) + data.count > 65536 { status.text = "待发送内容过多，请稍后再试"; return }; queued.append(data); flush() }
    func flush() {
        guard !sending, !queued.isEmpty, let id = p.terminalID, workspaceGeneration == p.terminalGeneration else { return }
        sending = true; let data = queued.removeFirst(); let wg = workspaceGeneration
        p.request("terminal/write", body: ["id": id, "data": data.base64EncodedString()]) { r in
            self.sending = false
            guard wg == self.p.terminalGeneration else { self.queued = []; return }
            if case .failure(let error) = r { self.status.text = "发送失败：" + error.localizedDescription; self.queued = []; return }; self.flush()
        }
    }
    @objc func restart() { confirm("新终端会话", "关闭旧 Shell 及其运行进程，然后新建。") {
        self.pause(); self.queued = []
        let done = { self.p.terminalID = nil; self.p.terminalGeneration += 1; self.resume() }
        if let id = self.p.terminalID { self.p.request("terminal/close", body: ["id": id]) { r in if case .failure(let e) = r { self.message(e.localizedDescription) } else { done() } } } else { done() }
    } }
}
