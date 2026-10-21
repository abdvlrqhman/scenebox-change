//
//  OriginalAudio.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

import Foundation

nonisolated enum OriginalAudio {
    private static let bibliographic: [String: String] = [
        "deu": "ger", "fra": "fre", "zho": "chi", "nld": "dut", "ell": "gre",
        "ces": "cze", "fas": "per", "ron": "rum", "msa": "may", "sqi": "alb",
        "hye": "arm", "isl": "ice", "kat": "geo", "mkd": "mac", "slk": "slo",
        "cym": "wel", "eus": "baq", "mya": "bur", "bod": "tib",
    ]

    /// A track speaks `code` (ISO 639-1 or -2) by its language tag, or by
    /// the language's English name in its labels ("English 5.1").
    static func matches(language: String?, labels: [String], code: String) -> Bool {
        let codes = candidateCodes(for: code)
        if let raw = language?.lowercased() {
            let base = raw.split(separator: "-").first.map(String.init) ?? raw
            if codes.contains(base) { return true }
        }
        if let name = englishName(for: code)?.lowercased() {
            if labels.contains(where: { $0.lowercased().contains(name) }) { return true }
        }
        return false
    }

    private static func candidateCodes(for code: String) -> Set<String> {
        var codes: Set<String> = [code.lowercased()]
        if let alpha3 = Locale.LanguageCode(code).identifier(.alpha3)?.lowercased() {
            codes.insert(alpha3)
            if let biblio = bibliographic[alpha3] { codes.insert(biblio) }
        }
        return codes
    }

    private static func englishName(for code: String) -> String? {
        Locale(identifier: "en_US").localizedString(forLanguageCode: code)
    }
}
