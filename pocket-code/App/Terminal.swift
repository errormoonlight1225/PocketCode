import UIKit

// The terminal owns its cells. UIKit's editable text storage must not own the cursor.
final class TerminalText: UIScrollView, UIKeyInput, UITextInputTraits {
    var output: ((Data) -> Void)?
    var pasteText: ((String) -> Void)?
    var font = Theme.mono(12) { didSet { updateSize() } }
    var keyboardAppearance: UIKeyboardAppearance = .dark
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardType: UIKeyboardType = .default
    var accessory: UIView?
    override var inputAccessoryView: UIView? { accessory }
    override var canBecomeFirstResponder: Bool { true }
    var hasText: Bool { true }
    var lines: [[String]] = []
    var cursor = CGPoint.zero
    var cursorVisible = true
    let canvas = TerminalCanvas()
    var cellWidth: CGFloat { ceil(("M" as NSString).size(withAttributes: [.font: font]).width) }
    var cellHeight: CGFloat { ceil(font.lineHeight) }
    override init(frame: CGRect) {
        super.init(frame: frame); backgroundColor = .black; canvas.owner = self; addSubview(canvas)
        showsHorizontalScrollIndicator = false; isDirectionalLockEnabled = true
        contentInsetAdjustmentBehavior = .never
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focus)))
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(menu(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc func focus() { becomeFirstResponder(); canvas.setNeedsDisplay() }
    @objc func menu(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }; becomeFirstResponder()
        UIMenuController.shared.setTargetRect(CGRect(origin: gesture.location(in: self), size: CGSize(width: 1, height: 1)), in: self)
        UIMenuController.shared.setMenuVisible(true, animated: true)
    }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        action == #selector(copy(_:)) || (action == #selector(paste(_:)) && UIPasteboard.general.hasStrings)
    }
    override func copy(_ sender: Any?) {
        let first = max(0, Int(contentOffset.y / cellHeight))
        let last = min(lines.count, first + Int(ceil(bounds.height / cellHeight)))
        guard first < last else { return }
        UIPasteboard.general.string = lines[first..<last].map { $0.joined().trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }
    override func paste(_ sender: Any?) { if let value = UIPasteboard.general.string { pasteText?(value) } }
    func insertText(_ text: String) { output?(Data(text.replacingOccurrences(of: "\n", with: "\r").utf8)) }
    func deleteBackward() { output?(Data([127])) }
    func display(_ screen: ANSIScreen) {
        lines = (screen.alternate == nil ? screen.history.map { ANSIScreen.cells($0) } : []) + screen.grid
        cursor = CGPoint(x: CGFloat(screen.x), y: CGFloat((screen.alternate == nil ? screen.history.count : 0) + screen.y))
        cursorVisible = screen.cursorVisible
        updateSize()
    }
    func updateSize() {
        let size = CGSize(width: bounds.width, height: max(bounds.height, CGFloat(lines.count) * cellHeight + 8))
        if contentSize != size { contentSize = size }
        canvas.frame = CGRect(x: 0, y: contentOffset.y, width: bounds.width, height: bounds.height)
        canvas.setNeedsDisplay()
    }
    override func layoutSubviews() { super.layoutSubviews(); updateSize(); if contentOffset.x != 0 { contentOffset.x = 0 } }
    override var keyCommands: [UIKeyCommand]? {
        let items: [(String, UIKeyModifierFlags)] = [(UIKeyCommand.inputUpArrow, []), (UIKeyCommand.inputDownArrow, []), (UIKeyCommand.inputLeftArrow, []), (UIKeyCommand.inputRightArrow, []), (UIKeyCommand.inputEscape, []), ("c", .control), ("d", .control), ("a", .control), ("e", .control), ("l", .control), ("u", .control), ("w", .control), ("z", .control), ("\t", [])]
        return items.map { UIKeyCommand(input: $0.0, modifierFlags: $0.1, action: #selector(key(_:))) }
    }
    @objc func key(_ command: UIKeyCommand) {
        guard let key = command.input else { return }
        let arrows = [UIKeyCommand.inputUpArrow: "\u{1b}[A", UIKeyCommand.inputDownArrow: "\u{1b}[B", UIKeyCommand.inputRightArrow: "\u{1b}[C", UIKeyCommand.inputLeftArrow: "\u{1b}[D", UIKeyCommand.inputEscape: "\u{1b}", "\t": "\t"]
        if command.modifierFlags.contains(.control), let byte = key.utf8.first { output?(Data([byte & 31])) } else if let value = arrows[key] { output?(Data(value.utf8)) }
    }
}
final class TerminalCanvas: UIView {
    weak var owner: TerminalText?
    override func draw(_ rect: CGRect) {
        guard let t = owner, let context = UIGraphicsGetCurrentContext() else { return }
        UIColor.black.setFill(); context.fill(rect)
        let first = max(0, Int((rect.minY + t.contentOffset.y - 4) / t.cellHeight))
        let last = min(t.lines.count, Int(ceil((rect.maxY + t.contentOffset.y) / t.cellHeight)))
        guard first < last else { return }
        for row in first..<last {
            for (col, value) in t.lines[row].enumerated() where value != " " && !value.isEmpty {
                let cell = CGRect(x: 4 + CGFloat(col) * t.cellWidth, y: 4 + CGFloat(row) * t.cellHeight - t.contentOffset.y, width: t.cellWidth * CGFloat(ANSIScreen.cellWidth(value)), height: t.cellHeight)
                context.saveGState(); context.clip(to: cell)
                (value as NSString).draw(at: cell.origin, withAttributes: [.font: t.font, .foregroundColor: Theme.mint])
                context.restoreGState()
            }
        }
        if t.isFirstResponder && t.cursorVisible {
            Theme.mint.withAlphaComponent(0.55).setFill()
            context.fill(CGRect(x: 4 + t.cursor.x * t.cellWidth, y: 4 + t.cursor.y * t.cellHeight - t.contentOffset.y, width: t.cellWidth, height: t.cellHeight))
        }
    }
}
final class TerminalController: UIViewController {
    let p = Pocket.shared
    let screen = ANSIScreen()
    let terminal = TerminalText(frame: .zero)
    let status = UILabel()
    var bottom: NSLayoutConstraint!
    var active = false, loading = false, sending = false, creating = false
    var generation = 0, offset = 0, workspaceGeneration = -1
    var queued: [Data] = []
    var keys: [String] = []
    var failures = 0
    var resizing = false
    var pendingResize: (String, Int, Int, Int)?
    var fontSize: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "terminalFontSize"))
    var pinchStart: CGFloat = 12
    var followOutput = true
    let live = UIButton(type: .system)
    var terminalFont: UIFont { Theme.mono(fontSize) }
    func render() {
        let previousOffset = terminal.contentOffset
        terminal.display(screen)
        terminal.layoutIfNeeded()
        if followOutput { scrollToBottom() } else {
            terminal.setContentOffset(CGPoint(x: 0, y: min(previousOffset.y, max(0, terminal.contentSize.height - terminal.bounds.height))), animated: false)
        }
    }
    func scrollToBottom() {
        terminal.setContentOffset(CGPoint(x: 0, y: max(-terminal.adjustedContentInset.top, terminal.contentSize.height - terminal.bounds.height + terminal.adjustedContentInset.bottom)), animated: false)
    }
    @objc func showLatest() { followOutput = true; scrollToBottom(); live.isHidden = true }
    @objc func beganScroll(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { followOutput = false; live.isHidden = false }
        if gesture.state == .ended || gesture.state == .cancelled {
            followOutput = terminal.contentOffset.y + terminal.bounds.height >= terminal.contentSize.height - 24
            live.isHidden = followOutput
        }
    }
    @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { pinchStart = fontSize }
        fontSize = min(24, max(9, (pinchStart * gesture.scale).rounded()))
        terminal.font = terminalFont; resize(); render()
        if gesture.state == .ended { UserDefaults.standard.set(Double(fontSize), forKey: "terminalFontSize") }
    }
    @objc func pasteClipboard() { if let value = UIPasteboard.general.string { pasteInput(value) } }
    func pasteInput(_ value: String) {
        guard !value.isEmpty else { return }
        let data = screen.pasteData(value)
        if !screen.bracketedPaste && (value.contains("\n") || value.contains("\r")) {
            confirm("粘贴多行命令", "当前 Shell 未开启安全粘贴模式，换行可能直接执行命令。确认粘贴？") { self.queue(data) }
        } else { queue(data) }
    }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = Theme.background
        if fontSize < 9 || fontSize > 24 { fontSize = 12 }
        terminal.backgroundColor = .black; terminal.font = terminalFont; terminal.autocorrectionType = .no; terminal.autocapitalizationType = .none; terminal.smartQuotesType = .no; terminal.smartDashesType = .no; terminal.keyboardAppearance = .dark
        terminal.smartInsertDeleteType = .no
        terminal.keyboardDismissMode = .interactive
        terminal.alwaysBounceVertical = true
        terminal.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
        terminal.panGestureRecognizer.addTarget(self, action: #selector(beganScroll(_:)))
        terminal.pasteText = { [weak self] value in self?.pasteInput(value) }
        terminal.output = { [weak self] data in self?.queue(data) }; screen.response = { [weak self] data in self?.queue(data, follow: false) }
        live.setTitle("↓ 回到底部", for: .normal); live.tintColor = Theme.mint; live.backgroundColor = .black; live.layer.cornerRadius = 12; live.isHidden = true
        live.addTarget(self, action: #selector(showLatest), for: .touchUpInside)
        live.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(live)
        status.font = Theme.mono(11); status.textColor = Theme.muted; status.numberOfLines = 2; status.text = "连接工作区后点击键盘"
        for v in [status, terminal] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        bottom = terminal.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        NSLayoutConstraint.activate([status.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8), status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8), status.heightAnchor.constraint(equalToConstant: 36), terminal.topAnchor.constraint(equalTo: status.bottomAnchor), terminal.leadingAnchor.constraint(equalTo: view.leadingAnchor), terminal.trailingAnchor.constraint(equalTo: view.trailingAnchor), bottom])
        view.bringSubviewToFront(live)
        NSLayoutConstraint.activate([live.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), live.bottomAnchor.constraint(equalTo: terminal.bottomAnchor, constant: -8), live.widthAnchor.constraint(equalToConstant: 116), live.heightAnchor.constraint(equalToConstant: 36)])
        navigationItem.rightBarButtonItems = [UIBarButtonItem(title: "键盘", style: .plain, target: self, action: #selector(toggleKeyboard)), UIBarButtonItem(title: "新会话", style: .plain, target: self, action: #selector(restart))]
        let bar = UIToolbar(); bar.barStyle = .black; bar.tintColor = Theme.mint; bar.sizeToFit()
        let pairs = [("Esc", "\u{1b}"), ("Tab", "\t"), ("^C", "\u{3}"), ("^D", "\u{4}"), ("^L", "\u{c}"), ("^U", "\u{15}"), ("↑", "\u{1b}[A"), ("↓", "\u{1b}[B"), ("←", "\u{1b}[D"), ("→", "\u{1b}[C")]
        keys = pairs.map { $0.1 }; bar.items = pairs.enumerated().map { i, item in let b = UIBarButtonItem(title: item.0, style: .plain, target: self, action: #selector(special(_:))); b.tag = i; return b }; bar.items?.append(UIBarButtonItem(title: "粘贴", style: .plain, target: self, action: #selector(pasteClipboard)))
        let accessory = UIScrollView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 44))
        accessory.autoresizingMask = [.flexibleWidth]; accessory.showsHorizontalScrollIndicator = false; accessory.alwaysBounceHorizontal = true
        bar.frame = CGRect(x: 0, y: 0, width: max(660, view.bounds.width), height: 44)
        accessory.addSubview(bar); accessory.contentSize = bar.bounds.size; terminal.accessory = accessory
        NotificationCenter.default.addObserver(self, selector: #selector(keyboard(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pause), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); resume() }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); pause() }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); resize() }
    func resize() {
        guard terminal.bounds.width > 0, terminal.bounds.height > 0 else { return }
        let width = max(10, Int((terminal.bounds.width - 8) / terminal.cellWidth))
        let height = max(3, Int((terminal.bounds.height - 8) / terminal.cellHeight))
        guard width != screen.cols || height != screen.rows else { return }; screen.resize(width, height); render()
        if active, let id = p.terminalID { sendResize(id: id, cols: width, rows: height) }
    }
    func sendResize(id: String, cols: Int, rows: Int) {
        pendingResize = (id, cols, rows, p.terminalGeneration); flushResize()
    }
    func flushResize() {
        guard !resizing, let size = pendingResize else { return }
        pendingResize = nil
        guard size.3 == p.terminalGeneration, size.0 == p.terminalID else { return }
        resizing = true
        p.request("terminal/resize", body: ["id": size.0, "cols": size.1, "rows": size.2]) { result in
            self.resizing = false
            if size.3 == self.p.terminalGeneration, case .failure(let error) = result { self.status.text = "调整终端失败：" + error.localizedDescription }
            self.flushResize()
        }
    }
    @objc func keyboard(_ n: Notification) {
        guard let f = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let frame = view.convert(f, from: nil)
        let intersection = view.bounds.intersection(frame)
        let coversBottom = !intersection.isNull && frame.maxY >= view.bounds.maxY
        bottom.constant = coversBottom ? -max(0, intersection.height - view.safeAreaInsets.bottom) : 0
        let duration = n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curve = n.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve << 16), animations: { self.view.layoutIfNeeded() })
    }
    @objc func special(_ b: UIBarButtonItem) { queue(Data(keys[b.tag].utf8)) }
    @objc func toggleKeyboard() { if terminal.isFirstResponder { terminal.resignFirstResponder(); terminal.canvas.setNeedsDisplay() } else { terminal.becomeFirstResponder(); terminal.canvas.setNeedsDisplay(); resume() } }
    @objc func pause() { active = false; generation += 1; loading = false }
    @objc func resume() {
        guard viewIfLoaded?.window != nil, p.connected, !active else { return }
        if workspaceGeneration != p.terminalGeneration { screen.reset(); terminal.display(screen); offset = 0; queued = []; workspaceGeneration = p.terminalGeneration }
        active = true; generation += 1; let g = generation; failures = 0
        if p.terminalID == nil {
            guard !creating else { return }; creating = true
            status.text = "正在创建原生 PTY…"
            let wg = p.terminalGeneration
            p.request("terminal/new", body: ["cols": screen.cols, "rows": screen.rows]) { r in
                self.creating = false
                do {
                    let j = try r.get(); guard let id = j["id"] as? String else { throw PocketError(message: "没有收到终端 ID") }
                    guard wg == self.p.terminalGeneration else { return }
                    // Retain a created shell even if the view was temporarily hidden.
                    self.p.terminalID = id; self.offset = 0
                    self.sendResize(id: id, cols: self.screen.cols, rows: self.screen.rows)
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
                    self.screen.feed(data); self.render()
                }
                self.offset = j["offset"] as? Int ?? self.offset; self.failures = 0
                self.status.text = "PTY · \(self.screen.cols)×\(self.screen.rows) · \(Int(self.fontSize))pt · 双指缩放"
                if j["truncated"] as? Bool == true { self.status.text = "旧输出超出服务缓存；显示最近内容" }
                if j["closed"] as? Bool == true { self.status.text = "Shell 已退出，请新建会话"; self.active = false; return }
            } catch { self.failures += 1; self.status.text = error.localizedDescription; if self.failures >= 5 { self.active = false; return } }
            DispatchQueue.main.asyncAfter(deadline: .now() + (self.failures == 0 ? 0.2 : 2)) { [weak self] in self?.poll(g) }
        }
    }
    func queue(_ data: Data, follow: Bool = true) { if follow { showLatest() }; guard p.connected, p.terminalID != nil, workspaceGeneration == p.terminalGeneration else { return }; if queued.reduce(0, { $0 + $1.count }) + data.count > 65536 { status.text = "待发送内容过多，请稍后再试"; return }; queued.append(data); flush() }
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
