import Foundation
import ArgumentParser

// make sure to first run: ollama run deepseek-r1:32b

@main
struct TranslatrixCommand: AsyncParsableCommand {
    @Flag(help: "Verbose output.")
    var verbose = false

    @Flag(help: "Force retranslation of existing translations.")
    var force = false

    @Flag(help: "Translate into all known languages.")
    var all = false

    @Option(help: "Translate into the top N languages.")
    var top: Int?

    @Flag(help: "Request an explanation for each translation.")
    var explain = false

    @Option(help: "Failed translation retry count.")
    var retries: Int = 5

    @Option(help: "The ollama URL to connect to.")
    var endpoint = "http://localhost:11434/api/generate"

    /// codellama seems to be the only one that doesn't mangle markdown like `[name](https://link)` into: `[name](<https://link>)`
    @Option(help: "The ollama model to use.")
    var model: String // = "codellama:34b-code" // "mistral" // = "deepseek-r1:32b"

    @Option(help: "Specific language codes to translate.")
    var lang: [String] = []

    @Option(help: ArgumentHelp("List of states to re-translate.", valueName: "states"))
    var retranslate: [String] = []

    @Option(help: "New translation state.")
    var state: String = .needs_review

    @Argument(help: "The Localizable.xcstrings files to translate.")
    var xcstrings: [String]

    /// All the common language codes that we might translate into
    private static let majorLanguageCodes = [
        // don't bother translating english -> english
        //"en",
        //"en_GB",

        "fr", // French
        "es", // Spanish
        "de", // German
        "it", // Italian
        "pt_PT", // Portuguese (Portgual)

        "es_419", // Spanish (Latin America)
        "pt_BR", // Portuguese (Brazilian)

        "zh_CN", // Chinese (Mainland) – 汉语
        "ja", // Japanese – 日本語 (Nihongo)
        "ko", // Korean – 한국어
        "zh_TW", // Chinese (Taiwan) – 漢語
        "th", // Thai – ภาษาไทย (Phasa Thai)
        "vi", // Vietnamese – tiếng Việt

        "uk", // Ukrainian – Українська (Ukraїnska)
        "el", // Greek – Νέα Ελληνικά; (Néa Ellêniká)
        "tr", // Turkish – Türkçe
        "ru", // Russian – Русский язык (Russkiĭ âzyk)

        "ar", // Arabic – اَلْعَرَبِيَّةُ (al-ʿarabiyyah)
        "hi", // Hindi – हिन्दी (Hindī)
        "id", // Indonesian – bahasa Indonesia
        "fa", // Persian – فارسی (Fārsiy)
        "he", // Hebrew – עברית‎ (Ivrit)

        "pl", // Polish – Polski
        "hu", // Hungarian – Magyar nyelv
        "da", // Danish – Dansk
        "fi", // Finnish – Suomi
        "sv", // Swedish – Svenska
        "nb", // Norwegian Bokmål – Norsk Bokmål
        "nl", // Dutch, Flemish – Nederlands

        "sk", // Slovak – Slovenčina
        "sl", // Slovenian – Slovenščina
        "sr", // Serbian – Српски (Srpski)
        "cs", // Czech – Čeština
        "et", // Estonian – Eesti keel
        "fil", // Filipino

        "sw", // Swahili – Kiswahili; كِسوَحِيلِ
        "af", // Afrikaans
        "am", // Amharic – አማርኛ (Amarəñña)
        "bg", // Bulgarian – Български (Bulgarski)
        "sq", // Albanian
        "az", // Azerbaijani
        "ka", // Georgian
        "ka", // Kazakh
        "uz", // Uzbek
        "bs", // Bosnian
        "mk", // Macedonian
        "bn", // Bengali – বাংলা (Bāŋlā)
        "ca", // Catalan, Valencian – Català; Valencià
        "gu", // Gujarati – ગુજરાતી (Gujarātī)
        "hr", // Croatian – Hrvatski
        "lt", // Lithuanian – Lietuvių
        "lv", // Latvian – Latviski
        "ml", // Malayalam – മലയാളം (Malayāļã)
        "mr", // Marathi – मराठी (Marāṭhī)
        "ms", // Malay – بهاس ملايو (bahasa Melayu)
        "ro", // Romanian – Românã
        "ta", // Tamil – தமிழ் (Tamiḻ)
        "te", // Telugu – తెలుగు (Telugu)
        "ur", // Urdu – اُردُو (Urduw)
        "kn", // Kannada – ಕನ್ನಡ (Kannađa)
    ]

    mutating func run() async throws {
        let sourceLanguage = "English"
        let retries = 8 // the number of times to retry is there is a failure

        for stringsFile in xcstrings {
            let stringsURL = URL(fileURLWithPath: stringsFile)

            var strings = try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: stringsURL))
            /// Save back the modified strings value to the localization dictionary
            func saveStrings() throws {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                let stringsData = try encoder.encode(strings)
                try stringsData.write(to: stringsURL)
            }

            let sourceLocale = Locale(identifier: strings.sourceLanguage)

            let terms = strings.strings.keys.sorted()

            print("Translating terms: \(terms)")

            // get the list of all the currently-localized languages in the file (sans the source language)
            // we use this to "fill in" any missing translations
            let localizationLanguageCodes = Set(strings.strings.values.compactMap(\.localizations).flatMap(\.keys).filter({ $0 != strings.sourceLanguage })).sorted()

            // selected from the language codes that are currently set in the translation
            let languageCodes = self.all ? Self.majorLanguageCodes // all major langues
                : !self.lang.isEmpty ? self.lang // manually specified languages
                : self.top != nil ? Array(Self.majorLanguageCodes.prefix(upTo: self.top!)) // top N languages from major languages
                : localizationLanguageCodes // the languages currenly specified in the Localizable.xcstrings

            for targetLanguageCode in languageCodes {

                for termKey in terms {
                    guard var values = strings.strings[termKey] else {
                        print("No value for key: \(termKey)")
                        continue
                    }

                    var localizations = values.localizations ?? [:]

                    // the translation term is either the key, or the source language translation (e.g., "en") of the key
                    let term = localizations[sourceLocale.identifier]?.stringUnit.value ?? termKey

                    if let targetTranslation = localizations[targetLanguageCode]?.stringUnit, !force {
                        if self.retranslate.contains(targetTranslation.state) {
                            print("Re-translating \(targetLanguageCode) state \(targetTranslation.state): '\(termKey)': “\(targetTranslation.value)”")
                        } else {
                            print("Already translated \(targetLanguageCode): '\(termKey)': “\(targetTranslation.value)”")
                            continue
                        }
                    }

                    guard let targetLanguageName = Locale(identifier: "en").localizedString(forIdentifier: targetLanguageCode) else {
                        print("Could not get language name from code: \(targetLanguageCode)")
                        continue
                    }

                    for attempt in 1...retries {
                        do {
                            let translation = try await translate(term: term, model: model, url: endpoint, sourceLanguage: sourceLanguage, targetLanguage: targetLanguageName, context: values.comment)
                            print("\(targetLanguageName) (\(targetLanguageCode)): \(translation.translation)")

                            localizations[targetLanguageCode] = .init(stringUnit: .init(state: self.state, value: translation.translation))
                            values.localizations = localizations
                            strings.strings[termKey] = values
                            try saveStrings() // re-save the strings every time we make a change

                            break
                        } catch {
                            print("Error in attempt #\(attempt): \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    func translate(term: String, model: String, url: String, sourceLanguage: String, targetLanguage: String, context: String?) async throws -> Translation {
        var desc = "Translating \"\(term)\" from \(sourceLanguage) to \(targetLanguage) using \(model)"
        if let context = context {
            desc += " with context: “\(context)”"
        }
        desc += "…"

        print(desc)

        let endpoint = URL(string: url)!
        var request = URLRequest(url: endpoint)
        var query = ""
        query += """
        You are a professional translator with expertise in mobile app localization. Please translate the following user interface string from \(sourceLanguage) to \(targetLanguage): "\(term)"
        
        """

        if self.explain {
            query += """
            The response JSON should be an object that contains only the keys "\(sourceLanguage)", "\(targetLanguage)", "explanation" and nothing else. The "explanation" value should be a very brief English description of why the translation was chosen.
            
            """
        } else {
            query += """
            The response JSON should be an object that contains ONLY the keys "\(sourceLanguage)" and "\(targetLanguage)" and nothing else.
            
            """
        }

        if let context = context {
            query += """
            
            Please take into account the following translation context: \(context)
            
            """
        }

        query += """
        
        Important instructions:
        
        - Maintain all placeholders prefixed with "%" (e.g., %@, %lld, %lf) exactly as they appear
        - Maintain any URLs or email addresses exactly as they appear
        - Preserve any markdown tags and their contents, including the exact contents of links
        - Do not output any HTML tags or other non-markdown styling
        - Keep the same line breaks and formatting
        - For buttons and short UI elements, prioritize concise translations
        - Maintain the same tone and formality level as the source text
        - There is no limit to the length of the response, so do not truncate any part of the response

        """


        if self.explain {
            query += """
            - Flag any culturally specific elements that might need adaptation
            - Include any relevant notes about context or ambiguity in the "explanation" field

            """
        }

        //try query = query + String(contentsOfFile: xcstringsFile, encoding: .utf8)

        //print("query: \(query)")

        //query = "Translate the words 'Hello', 'Goodbye', 'Screen', 'Appearance', and 'Computer' from English to \(lang) in the form of an xcstrings translation JSON file"

        let prompt = Prompt(model: model, prompt: query, format: "json", stream: false)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(prompt)
        request.timeoutInterval = 2400.0 // 30 minutes should be enough

        let (data, response) = try await URLSession.shared.data(for: request)
        let responseString = String(data: data, encoding: .utf8) ?? ""
        if !(200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0) {
            throw TranslationError("HTTP error contacting \(url) (is ollama running the model?): \(response) \(responseString)")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reply = try decoder.decode(PromptReply.self, from: data)
        let answerString = (reply.response ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonAnswer = try JSONSerialization.jsonObject(with: answerString.data(using: .utf8)!)
        let formattedJSONAnswer = try JSONSerialization.data(withJSONObject: jsonAnswer, options: [.prettyPrinted, .withoutEscapingSlashes])

        if verbose {
            print("Response: " + String(data: formattedJSONAnswer, encoding: .utf8)!)
        }

        guard let resultDict = jsonAnswer as? [String: String] else {
            throw TranslationError("JSON response was not a dictionary: \(answerString)")
        }

        guard let sourceString = resultDict[sourceLanguage] else {
            throw TranslationError("JSON response did not contain a '\(sourceLanguage)' key: \(answerString)")
        }

        if sourceString != term {
            throw TranslationError("JSON response '\(sourceLanguage)' value did not match query '\(term)': \(answerString)")
        }

        guard let targetString = resultDict[targetLanguage] else {
            throw TranslationError("JSON response did not contain a '\(targetLanguage)' key: \(answerString)")
        }

        if targetString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TranslationError("JSON response for '\(targetLanguage)' was empty: \(answerString)")
        }

        let explanation = resultDict["explanation"]
        if self.explain && explanation == nil {
            throw TranslationError("JSON response did not contain a 'explanation' key: \(answerString)")
        }

        for token in ["%@", "%d", "%lld", "%lf"] {
            let sourceParts = sourceString.split(separator: token, omittingEmptySubsequences: false)
            let targetParts = targetString.split(separator: token, omittingEmptySubsequences: false)
            if sourceParts.count != targetParts.count {
                throw TranslationError("Response for '\(targetLanguage)' token count \(token) was not the same in the output: \(targetString)")
            }
        }

        return Translation(source: sourceString, translation: targetString, explanation: explanation)
    }

}


struct StringCatalog: Codable {
    //var projectName: String?
    var sourceLanguage: String
    var strings: [String: StringData] = [:]
    var version: String

    struct StringData: Codable {
        var comment: String?
        var extractionState: String? // "manual", "migrated"
        var localizations: [String: Localization]?
    }

    struct Localization: Codable {
        var stringUnit: StringUnit
        var variations: Variations?
    }

    struct StringUnit: Codable {
        var state: String
        var value: String
    }

    struct Variations: Codable {
        var plural: PluralVariation?
    }

    struct PluralVariation: Codable {
        var zero: Variation?
        var one: Variation?
        var two: Variation?
        var few: Variation?
        var many: Variation?
        var other: Variation

        var all: [Variation] { [zero, one, two, few, many, other].compactMap { $0 } }
    }

    struct Variation: Codable {
        var stringUnit: StringUnit
        var state: String
    }
}

extension String {
    /// Extension for `translationState`
    static let new = "new"
    /// Extension for `translationState`
    static let stale = "stale"
    /// Extension for `translationState`
    static let needs_review = "needs_review"
    /// Extension for `translationState`
    static let translated = "translated"
}


struct TranslationError : LocalizedError {
    var failureReason: String?

    init(_ failureReason: String) {
        self.failureReason = failureReason
    }
}

struct Translation {
    var source: String
    var translation: String
    var explanation: String?
}

struct Prompt : Encodable {
    var model: String
    var prompt: String
    var images: [String]? = nil
    var system: String? = nil
    var template: String? = nil
    var context: [Int]? = nil
    var options: [String: String]? = nil
    var keep_alive: String? = nil
    var format: String? = nil
    var raw: Bool? = nil
    var stream: Bool? = nil
}

struct PromptReply : Codable {
    let model: String?
    let created_at: String? // Date // 2025-01-26T20:22:30.00907Z // "Expected date string to be ISO8601-formatted."
    let response: String?
    let done: Bool
    let done_reason: String?
    // unused fields:
    //let context: [Int64]?
    //let total_duration: Int64?
    //let load_duration: Int64?
    //let prompt_eval_count: Int?
    //let prompt_eval_duration: Int64?
    //let eval_count: Int?
    //let eval_duration: Int64?
}


//private let sampleTerms = [
//    //Navigation and Tabs
//
//    "Home",
//    "Menu",
//    "Back",
//    "Next",
//    "Previous",
//    "Continue",
//    "Done",
//    "Close",
//    "Exit",
//    "More",
//    "Settings",
//    "Profile",
//    "Notifications",
//    "Search",
//    "Discover",
//    "Buttons and Actions",
//
//    "Log In",
//    "Sign Up",
//    "Register",
//    "Submit",
//    "Save",
//    "Cancel",
//    "Delete",
//    "Edit",
//    "Add",
//    "Remove",
//    "Download",
//    "Upload",
//    "Share",
//    "Send",
//    "Confirm",
//
//    // User Account and Authentication
//
//    "Forgot Password?",
//    "Reset Password",
//    "Change Password",
//    "Log Out",
//    "Sign In with Google",
//    "Sign In with Apple",
//    "Verify Email",
//    "Two-Factor Authentication",
//    "Privacy Policy",
//    "Terms of Service",
//    "Support and Help",
//
//    "Help",
//    "Support",
//    "Contact Us",
//    "FAQ (Frequently Asked Questions)",
//    "Report a Problem",
//    "Feedback",
//    "Rate Us",
//    "About Us",
//    "Version",
//    "Tutorial",
//    "Walkthrough",
//]
