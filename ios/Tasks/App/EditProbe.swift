import UIKit

#if DEBUG || PERF_PROBE
/// Debug builds and the phone's measuring build (`PERF_PROBE`, ios/Tools/perf/README.md) only.
///
/// `-editTrace YES` (FoldFilmTests' editing films): while a row of a list is typed into (`CollectionEditing.item`),
/// every display frame, to tmp/edit-trace.log in the app's container:
///   F <epoch s> off=<content offset y, as drawn>/<model> ins=<bottom inset> cell=<the row's top>,<height> as drawn
///   (model) next=<the next row's top, as drawn> tv=<the text view's top in the window>,<height> bo=<its own bounds y>
///   cs=<its content height> caret=<the drawn caret's top in the window>,<height> (model caret's top) len=<text length>
///   nl=<new lines>
/// Then the row's own layers: "layers=<n>new/<n>gone" when its layers were replaced, "lchg=" each layer whose place in
/// the row or opacity changed since the last frame (as drawn), "anims=" each with a Core Animation animation running.
/// All y in the window's points. Marks: "M <epoch s> …": each change of the text ("text"), the rows resized
/// ("resize"/"reconfigure"), a caret scroll asked for and made ("ask"/"scroll"), the keyboard's inset ("keyboard"); with
/// the text view's and the row's sizes at each change, a run-loop turn later and 300 ms later (`sizes`). The row is
/// traced on for 1.5 s after it stops being typed into.
///
/// `-editProbe YES` (FlowTests): the same, as the accessibility value of an element "editProbe", for the frame now:
/// "caret=<y>,<h> mcaret=<y> tv=<y>,<h> bo=<y> cs=<h> nl=<n> shown=<1 if the drawn caret is inside
/// the text view's bounds (if it clips) and the row's cell>".
@MainActor
final class EditProbe {
    static let shared = EditProbe()
    let tracing = UserDefaults.standard.bool(forKey: "editTrace")
    let probing = UserDefaults.standard.bool(forKey: "editProbe")
    private var on: Bool { tracing || probing }
    private weak var cv: UICollectionView?
    private var item: () -> String? = { nil }
    private var link: CADisplayLink?
    private var lines: [String] = []
    private var file: FileHandle?
    private let disk = DispatchQueue(label: "editProbe.disk", qos: .utility)
    private var flushed: CFTimeInterval = 0
    private let epoch = Date().timeIntervalSince1970 - CACurrentMediaTime()
    private let marker: UIView = {
        let v = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        v.isUserInteractionEnabled = false
        v.isAccessibilityElement = true
        v.accessibilityIdentifier = "editProbe"
        v.accessibilityValue = "caret=-"
        return v
    }()

    private init() {}

    /// The list's collection view, and the row being typed into on it.
    func install(_ cv: UICollectionView, item: @escaping () -> String?) {
        guard on else { return }
        self.cv = cv
        self.item = item
        if tracing, file == nil {
            file = Trace.open("edit-trace.log")
            mark("launch editTrace")
        }
        guard link == nil else { return }
        let l = CADisplayLink(target: Fire.shared, selector: #selector(Fire.fire(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        NotificationCenter.default.addObserver(forName: UITextView.textDidChangeNotification, object: nil, queue: nil) { n in
            let tv = n.object as? UITextView
            let s = tv?.text ?? ""
            MainActor.assumeIsolated {
                let p = EditProbe.shared
                p.mark("text len=\(s.utf16.count) nl=\(s.filter { $0 == "\n" }.count) " + p.sizes())
                DispatchQueue.main.async { p.mark("text+0 " + p.sizes()) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { p.mark("text+300 " + p.sizes(full: true)) }
            }
        }
        for n in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { EditProbe.shared.flush() }
            }
        }
    }

    func mark(_ s: String) {
        guard tracing else { return }
        lines.append(String(format: "M %.4f ", CACurrentMediaTime() + epoch) + s)
    }

    private var editing = false
    private var marked: String?
    private var layers: Set<ObjectIdentifier> = []
    private var look: [ObjectIdentifier: String] = [:]
    private var hosting = ""
    /// The row last typed into, traced on for a while after it ends (the editor's going, the keyboard's).
    private var last: (id: String, until: CFTimeInterval)?

    /// The edited row's text view and cell, measured now: what it would fit (`fit`), its content and intrinsic heights,
    /// its bounds, the model caret's top in it, and the cell's fitted height.
    func sizes(full: Bool = false) -> String {
        guard tracing, let cv, let id = item() ?? last?.id, let ds = cv.dataSource as? UICollectionViewDiffableDataSource<Int, String>,
              let ip = ds.indexPath(for: id), let cell = cv.cellForItem(at: ip), let tv = Self.textView(in: cell) else { return "-" }
        let caret0 = tv.selectedTextRange.map { tv.caretRect(for: $0.end).minY } ?? .nan
        guard full else { return "cs=\(f(tv.contentSize.height)) bh=\(f(tv.bounds.height)) caret=\(f(caret0)) cell=\(f(cell.bounds.height))" }
        let fit = tv.sizeThatFits(CGSize(width: tv.bounds.width, height: .greatestFiniteMagnitude)).height
        let caret = tv.selectedTextRange.map { tv.caretRect(for: $0.end).minY } ?? .nan
        let cellFit = cell.contentView.systemLayoutSizeFitting(CGSize(width: cell.bounds.width, height: 0),
                                                               withHorizontalFittingPriority: .required,
                                                               verticalFittingPriority: .fittingSizeLevel).height
        let tk2 = tv.textLayoutManager != nil
        return "fit=\(f(fit)) cs=\(f(tv.contentSize.height)) ics=\(f(tv.intrinsicContentSize.height)) bh=\(f(tv.bounds.height)) caret=\(f(caret)) cell=\(f(cell.bounds.height)) cellFit=\(f(cellFit)) tk2=\(tk2 ? 1 : 0)"
    }

    private func frame() {
        guard let cv, let window = cv.window else { return }
        if marker.superview !== window { window.addSubview(marker) }
        let now0 = CACurrentMediaTime()
        if let id = item() { last = (id, now0 + 1.5) } else if let l = last, now0 > l.until { last = nil }
        guard let id = item() ?? last?.id, let ds = cv.dataSource as? UICollectionViewDiffableDataSource<Int, String>,
              let ip = ds.indexPath(for: id), let cell = cv.cellForItem(at: ip) else {
            if editing { editing = false; mark("traced row gone"); flush() }
            return
        }
        if item() == nil, editing, last?.id == id, marked != id { marked = id; mark("editing ended") }
        if !editing { editing = true; marked = nil; mark("editing \(id)") }
        let now = CACurrentMediaTime()
        let cvp = cv.layer.presentation() ?? cv.layer
        let top = cv.convert(CGPoint.zero, to: window).y + cv.contentOffset.y   // the content's origin, unscrolled
        let shownOff = cvp.bounds.minY
        // In the window, as drawn: content y − the drawn offset.
        func shown(_ y: CGFloat) -> CGFloat { top + y - shownOff }
        let cp = cell.layer.presentation() ?? cell.layer
        var out = String(format: "F %.4f", now + epoch)
        out += " off=\(f(shownOff))/\(f(cv.contentOffset.y)) ins=\(f(cv.contentInset.bottom))"
        out += " cell=\(f(shown(cp.frame.minY))),\(f(cp.frame.height)) (\(f(shown(cell.frame.minY))),\(f(cell.frame.height)))"
        let next = IndexPath(item: ip.item + 1, section: 0)
        if let n = cv.cellForItem(at: next) {
            out += " next=\(f(shown((n.layer.presentation() ?? n.layer).frame.minY)))"
        }
        var value = "caret=-"
        if let tv = Self.textView(in: cell) {
            // The text view inside the cell, as laid out (SwiftUI doesn't animate its frame), moved with the cell.
            let inCell = tv.convert(tv.bounds, to: cell)
            let tvTop = shown(cp.frame.minY) + inCell.minY
            // A rect in the text view's own space (its content, scrolled by its bounds) in the window, as drawn.
            func onScreen(_ y: CGFloat) -> CGFloat { tvTop + y - tv.bounds.minY }
            out += " tv=\(f(tvTop)),\(f(tv.bounds.height)) bo=\(f(tv.bounds.minY)) cs=\(f(tv.contentSize.height))"
            var caretY = CGFloat.nan, caretH = CGFloat.nan, model = CGFloat.nan
            if let r = tv.selectedTextRange {
                let m = tv.caretRect(for: r.end)
                model = onScreen(m.minY)
                caretH = m.height
            }
            // The caret as drawn: the selection display's cursor view.
            if let d = tv.interactions.compactMap({ $0 as? UITextSelectionDisplayInteraction }).first {
                let cur = d.cursorView
                if let sv = cur.superview, !cur.isHidden {
                    let r = sv.convert((cur.layer.presentation() ?? cur.layer).frame, to: tv)
                    caretY = onScreen(r.minY)
                    caretH = r.height
                }
            }
            let text = tv.text ?? ""
            let nl = text.filter { $0 == "\n" }.count
            out += " caret=\(f(caretY)),\(f(caretH)) (\(f(model))) len=\(text.utf16.count) nl=\(nl)"
            // Inside the text view's bounds and the cell's (both clip).
            let cy = caretY.isNaN ? model : caretY
            let foot = cy + (caretH.isNaN ? 0 : caretH)
            // (Its own bottom only if it clips: the in-place notes' text view draws its last line's gap past it.)
            let inside = cy + 1 >= tvTop && (!tv.clipsToBounds || foot <= tvTop + tv.bounds.height + 1)
                && foot <= shown(cp.frame.minY) + cp.frame.height + 1
            // (Not `layoutManager`: asking for it moves a TextKit 2 text view back to TextKit 1.)
            value = "caret=\(f(caretY)),\(f(caretH)) mcaret=\(f(model)) tv=\(f(tvTop)),\(f(tv.bounds.height)) bo=\(f(tv.bounds.minY)) cs=\(f(tv.contentSize.height)) nl=\(nl) shown=\(inside ? 1 : 0) cell=\(f(cell.frame.height))"
        }
        if tracing {
            // The row's own layers: any with an animation running (its keys), and when they're new ones.
            var anims: [String] = []
            var ids: [ObjectIdentifier] = []
            var looks: [ObjectIdentifier: String] = [:]
            let root = cell.contentView.layer
            func walk(_ l: CALayer, _ depth: Int) {
                guard depth < 12 else { return }
                ids.append(ObjectIdentifier(l))
                let p = l.presentation() ?? l
                let r = root.convert(p.bounds, from: l)
                looks[ObjectIdentifier(l)] = "\(type(of: l))@\(f(r.minY)),\(f(r.height)) a\(String(format: "%.2f", p.opacity))\(p.isHidden ? "h" : "")"
                if let keys = l.animationKeys(), !keys.isEmpty {
                    let p = l.presentation() ?? l
                    anims.append("\(type(of: l))@\(f(l.frame.minY))/\(f(p.frame.minY)) a\(String(format: "%.2f", p.opacity)) [\(keys.joined(separator: ","))]")
                }
                l.sublayers?.forEach { walk($0, depth + 1) }
            }
            walk(cell.contentView.layer, 0)
            // The cell's content views (the hosting view): place, safe area, what SwiftUI would fit in its width.
            let hv = cell.contentView.subviews.map { v -> String in
                let fit = v.sizeThatFits(CGSize(width: v.bounds.width, height: 0)).height
                return "\(type(of: v))@\(f(v.frame.minY)),\(f(v.frame.height)) sa=\(f(v.safeAreaInsets.top)),\(f(v.safeAreaInsets.bottom)) fit=\(f(fit))"
            }.joined(separator: ";")
            if hv != hosting { out += " hv=" + hv; hosting = hv }
            let changed = looks.compactMap { k, v in look[k].flatMap { $0 != v ? "\($0)→\(v)" : nil } }
            if !changed.isEmpty { out += " lchg=" + changed.prefix(8).joined(separator: ";") }
            look = looks
            let set = Set(ids)
            if set != layers {
                if !layers.isEmpty { out += " layers=\(set.subtracting(layers).count)new/\(layers.subtracting(set).count)gone" }
                layers = set
            }
            if !anims.isEmpty { out += " anims=" + anims.joined(separator: ";") }
        }
        if probing { marker.accessibilityValue = value }
        if tracing {
            lines.append(out)
            if now - flushed > 1 { flush() }
        }
    }

    static func textView(in v: UIView) -> UITextView? {
        if let t = v as? UITextView { return t }
        for s in v.subviews { if let t = textView(in: s) { return t } }
        return nil
    }

    func flush() {
        flushed = CACurrentMediaTime()
        guard !lines.isEmpty, let file else { return }
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        lines.removeAll(keepingCapacity: true)
        let h = Trace.Handle(file)
        disk.async { h.write(data) }
    }

    @MainActor private final class Fire: NSObject {
        static let shared = Fire()
        @objc func fire(_ l: CADisplayLink) { EditProbe.shared.frame() }
    }
}

private func f(_ v: CGFloat) -> String { v.isNaN ? "-" : String(format: "%.1f", v) }
#endif
