import UIKit
final class EditorController: UIViewController, UITextViewDelegate {
    let p = Pocket.shared
    let id: String
    let editor = UITextView()
    let status = UILabel()
    var draft: DispatchWorkItem?
    var bottom: NSLayoutConstraint!
    var saving = false
    init(id: String) { self.id = id; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    deinit { draft?.cancel(); NotificationCenter.default.removeObserver(self) }
    override func viewDidLoad() {
        super.viewDidLoad(); title = (id as NSString).lastPathComponent; view.backgroundColor = Theme.background
        editor.backgroundColor = Theme.background; editor.textColor = Theme.foreground; editor.tintColor = Theme.mint; editor.font = Theme.mono(14); editor.delegate = self
        editor.autocorrectionType = .no; editor.autocapitalizationType = .none; editor.smartQuotesType = .no; editor.smartDashesType = .no; editor.smartInsertDeleteType = .no; editor.keyboardAppearance = .dark
        editor.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        editor.text = p.documents.first { $0.id == id }?.text ?? ""
        status.font = Theme.mono(11); status.textColor = Theme.muted; status.numberOfLines = 1
        for v in [editor, status] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        bottom = editor.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        NSLayoutConstraint.activate([status.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14), status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8), status.heightAnchor.constraint(equalToConstant: 28), editor.topAnchor.constraint(equalTo: status.bottomAnchor), editor.leadingAnchor.constraint(equalTo: view.leadingAnchor), editor.trailingAnchor.constraint(equalTo: view.trailingAnchor), bottom])
        navigationItem.rightBarButtonItems = [UIBarButtonItem(title: "保存", style: .done, target: self, action: #selector(save)), UIBarButtonItem(title: "查找", style: .plain, target: self, action: #selector(findText))]
        let bar = UIToolbar(); bar.barStyle = .black; bar.tintColor = Theme.mint; bar.sizeToFit()
        bar.items = [UIBarButtonItem(title: "Tab", style: .plain, target: self, action: #selector(tabKey)), UIBarButtonItem(title: "{ }", style: .plain, target: self, action: #selector(braces)), UIBarButtonItem(barButtonSystemItem: .undo, target: self, action: #selector(undo)), UIBarButtonItem(title: "行", style: .plain, target: self, action: #selector(goLine)), UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), UIBarButtonItem(title: "收起", style: .plain, target: self, action: #selector(hideKeyboard))]
        editor.inputAccessoryView = bar
        NotificationCenter.default.addObserver(self, selector: #selector(keyboard(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        highlight(); updateStatus()
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); draft?.cancel(); persist() }
    @objc func keyboard(_ n: Notification) {
        guard let frame = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let overlap = view.bounds.intersection(view.convert(frame, from: nil)).height
        bottom.constant = -max(0, overlap - view.safeAreaInsets.bottom)
        UIView.animate(withDuration: n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25) { self.view.layoutIfNeeded() }
    }
    @objc func tabKey() { editor.insertText("    ") }
    @objc func braces() { editor.insertText("{}") }
    @objc func undo() { editor.undoManager?.undo() }
    @objc func hideKeyboard() { editor.resignFirstResponder() }
    func textViewDidChange(_ textView: UITextView) {
        guard let i = p.documents.firstIndex(where: { $0.id == id }) else { return }
        p.documents[i].text = editor.text; updateStatus(); draft?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.highlight(); self?.persist() }; draft = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }
    func textViewDidChangeSelection(_ textView: UITextView) { updateStatus() }
    func updateStatus() {
        let s = editor.text as NSString? ?? ""; let end = min(editor.selectedRange.location, s.length); let prefix = s.substring(to: end)
        let lines = prefix.components(separatedBy: "\n"); let dirty = p.documents.first { $0.id == id }?.dirty ?? false
        status.text = "Ln \(lines.count)  Col \((lines.last?.count ?? 0) + 1)  ·  \(dirty ? "未保存 · 本地草稿" : "已保存")"
    }
    func persist() { do { try p.persist() } catch { status.text = "草稿保存失败：" + error.localizedDescription } }
    func highlight() {
        guard editor.markedTextRange == nil else { return }
        let text = editor.text ?? ""; guard text.utf16.count < 300_000 else { return }
        let all = NSRange(location: 0, length: text.utf16.count)
        editor.textStorage.beginEditing(); editor.textStorage.addAttributes([.foregroundColor: Theme.foreground, .font: Theme.mono(14)], range: all)
        let patterns: [(String, UIColor)] = [("\\b(func|let|var|class|struct|enum|if|else|return|import|def|async|await|const|function|export|from|for|while|try|catch|throw|public|private|true|false|nil|null|None)\\b", Theme.mint), ("\\b[0-9]+(?:\\.[0-9]+)?\\b", UIColor.orange), ("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'", UIColor(red: 0.85, green: 0.78, blue: 0.49, alpha: 1)), ("(?m)//[^\\n]*|#[^\\n]*", Theme.muted)]
        for (pattern, color) in patterns { if let re = try? NSRegularExpression(pattern: pattern) { for m in re.matches(in: text, range: all) { editor.textStorage.addAttribute(.foregroundColor, value: color, range: m.range) } } }
        editor.textStorage.endEditing()
    }
    @objc func save() {
        guard !saving, let doc = p.documents.first(where: { $0.id == id }) else { return }; saving = true
        p.request("file", body: ["path": id, "content": doc.text, "revision": doc.revision]) { r in
            self.saving = false
            do { let j = try r.get(); if let i = self.p.documents.firstIndex(where: { $0.id == self.id }) { self.p.documents[i].saved = doc.text; self.p.documents[i].revision = j["revision"] as? String ?? "" }; self.persist(); self.updateStatus() } catch { self.message(error.localizedDescription) }
        }
    }
    @objc func findText() {
        let a = UIAlertController(title: "查找与替换", message: "替换全部会修改本地文档，保存后才写入远端。", preferredStyle: .alert)
        a.addTextField { $0.placeholder = "查找" }; a.addTextField { $0.placeholder = "替换为" }
        a.addAction(UIAlertAction(title: "下一个", style: .default) { _ in
            let query = a.textFields?[0].text ?? ""; guard !query.isEmpty else { return }; let s = self.editor.text as NSString? ?? ""; let start = min(NSMaxRange(self.editor.selectedRange), s.length)
            var range = s.range(of: query, options: [], range: NSRange(location: start, length: s.length - start)); if range.location == NSNotFound { range = s.range(of: query) }
            if range.location == NSNotFound { self.message("没有找到") } else { self.editor.selectedRange = range; self.editor.scrollRangeToVisible(range) }
        })
        a.addAction(UIAlertAction(title: "替换全部", style: .default) { _ in
            let query = a.textFields?[0].text ?? ""; guard !query.isEmpty else { return }
            self.editor.selectedRange = NSRange(location: 0, length: self.editor.text.utf16.count)
            self.editor.insertText(self.editor.text.replacingOccurrences(of: query, with: a.textFields?[1].text ?? ""))
        }); a.addAction(UIAlertAction(title: "取消", style: .cancel)); present(a, animated: true)
    }
    @objc func goLine() { prompt("跳转到行", placeholder: "行号") { value in
        guard let line = Int(value), line > 0 else { return }; let lines = self.editor.text.components(separatedBy: "\n"); guard line <= lines.count else { return }
        let offset = lines.prefix(line - 1).reduce(0) { $0 + $1.utf16.count + 1 }; self.editor.selectedRange = NSRange(location: offset, length: 0); self.editor.scrollRangeToVisible(self.editor.selectedRange)
    } }
}
