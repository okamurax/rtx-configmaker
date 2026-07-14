import Foundation

// 行単位の差分。
// ・前後の空白は無視して比較 (インデント差で誤検出しないため)
// ・内容が1文字でも違えば別の行として扱う
// ・順序は問わず「片方にしか無い行」を抽出 (重複行は出現回数で相殺)
enum ConfigDiff {

    static func compare(generated: String, existing: String, ignoreTrivial: Bool)
        -> (genOnly: [String], existOnly: [String]) {

        // 改行を正規化 (CRLF / CR → LF)。ターミナルやWindowsからの貼り付けで
        // 末尾CRが残り全行が偽差分になるのを防ぐ。
        func normalize(_ s: String) -> [String] {
            var lines = s.replacingOccurrences(of: "\r\n", with: "\n")
                         .replacingOccurrences(of: "\r", with: "\n")
                         .components(separatedBy: "\n")
            // 末尾の改行由来の空要素を除去 (末尾改行の有無で偽差分を出さない)
            while lines.last == "" { lines.removeLast() }
            return lines
        }
        let genLines = normalize(generated)
        let exLines  = normalize(existing)

        func key(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func skip(_ s: String) -> Bool {
            guard ignoreTrivial else { return false }
            let k = key(s)
            return k.isEmpty || k.hasPrefix("#")
        }

        // 既存側の (正規化キー -> 残数) を集計
        var existCount: [String: Int] = [:]
        for line in exLines where !skip(line) {
            existCount[key(line), default: 0] += 1
        }

        // 生成側: 既存に無ければ「生成だけ」、あれば相殺
        var genOnly: [String] = []
        for line in genLines where !skip(line) {
            let k = key(line)
            if let c = existCount[k], c > 0 {
                existCount[k] = c - 1
            } else {
                genOnly.append(line)
            }
        }

        // 既存側: 相殺されずに残った行が「既存だけ」
        var existOnly: [String] = []
        for line in exLines where !skip(line) {
            let k = key(line)
            if let c = existCount[k], c > 0 {
                existOnly.append(line)
                existCount[k] = c - 1
            }
        }

        return (genOnly, existOnly)
    }
}
