//
//  OriginalAudio.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

import Foundation

nonisolated enum OriginalAudio {
    /// The language a title was most likely made in, from its first country
    /// ("France, Belgium" → "fr"). A fallback for when TMDB can't say; nil for
    /// countries with no single language.
    static func language(forCountries countries: String?) -> String? {
        guard let first = countries?.split(separator: ",").first?.trimmingCharacters(in: .whitespaces),
              !first.isEmpty else { return nil }
        return countryLanguages[first.lowercased()]
    }

    private static let countryLanguages: [String: String] = [
        "united states": "en", "usa": "en", "united kingdom": "en", "uk": "en", "ireland": "en",
        "australia": "en", "new zealand": "en", "canada": "en",
        "france": "fr", "italy": "it", "spain": "es", "mexico": "es", "argentina": "es", "colombia": "es",
        "chile": "es", "germany": "de", "west germany": "de", "austria": "de", "japan": "ja",
        "south korea": "ko", "korea": "ko", "china": "zh", "hong kong": "zh", "taiwan": "zh",
        "india": "hi", "turkey": "tr", "türkiye": "tr", "brazil": "pt", "portugal": "pt", "russia": "ru",
        "soviet union": "ru", "sweden": "sv", "norway": "no", "denmark": "da", "finland": "fi",
        "netherlands": "nl", "poland": "pl", "egypt": "ar", "saudi arabia": "ar", "lebanon": "ar",
        "iran": "fa", "israel": "he", "thailand": "th", "greece": "el", "czech republic": "cs",
        "czechia": "cs", "hungary": "hu", "romania": "ro", "ukraine": "uk", "indonesia": "id",
        "philippines": "tl", "vietnam": "vi",
    ]

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
