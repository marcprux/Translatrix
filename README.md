# Translatrix

Translatrix is tool to help translate Localizable.xcstrings files using a local LLM

![Screenshot of Xcode with translation](screenshot.png?raw=true "Translatrix Localizable.xcstrings")

## Installation

Install [mint](https://github.com/yonaskolb/Mint#installing) and run:

```
mint install marcprux/translatrix
```

## Quickstart

1. Install [ollama](https://ollama.com) with `brew install ollama` then launch `ollama.app`
2. Install and run any [LLM model](https://github.com/ollama/ollama#model-library), like `ollama run [codellama:34b](https://ollama.com/library/codellama:34b)`
3. Launch Xcode and create a new "Multiplatform App" (e.g., named "SampleApp") on your Desktop
4. Run `File`/`New`/`File from Template` and select `String Catalog` and name it `Localizable.xcstrings`
5. Build and run the app and observe: "Hello, world!"
6. Run `translatrix --model codellama:34b-code --lang fr ~/Desktop/SampleApp/SampleApp/Localizable.xcstrings`
7. Switch your device/simulator language to French and re-launch the app, and observe: "Bonjour, le monde!"
8. Any time you add a localizable string to your app, re-run translatrix to update the xcstrings with new translations
9. Strings will be added with the "Needs Review" state in order to facilitate human approval of translations


### Details

When running the above command, the `Localizable.xcstrings` file goes from:

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "Hello, world!" : {

    }
  },
  "version" : "1.0"
}
```

to one that includes the French translation:

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "Hello, world!" : {
      "localizations" : {
        "fr" : {
          "stringUnit" : {
            "state" : "needs_review",
            "value" : "Bonjour, le monde!"
          }
        }
      }
    }
  },
  "version" : "1.0"
}
```

## Options

```
USAGE: translatrix-command [--verbose] [--force] [--all] [--top <top>] [--explain] [--retries <retries>] [--endpoint <endpoint>] --model <model> [--lang <lang> ...] [--retranslate <states> ...] [--state <state>] <xcstrings> ...

ARGUMENTS:
  <xcstrings>             The Localizable.xcstrings files to translate.

OPTIONS:
  --verbose               Verbose output.
  --force                 Force retranslation of existing translations.
  --all                   Translate into all known languages.
  --top <top>             Translate into the top N languages.
  --explain               Request an explanation for each translation.
  --retries <retries>     Failed translation retry count. (default: 5)
  --endpoint <endpoint>   The ollama URL to connect to. (default:
                          http://localhost:11434/api/generate)
  --model <model>         The ollama model to use.
  --lang <lang>           Specific language codes to translate.
  --retranslate <states>  List of states to re-translate.
  --state <state>         New translation state. (default: needs_review)
  -h, --help              Show help information.
```

### Guiding translations

Editing the `comment` fields in the `Localizable.xcstrings` will be used to
create the prompt for the LLM, and so can help disambiguate the terms that
may be used for various UI elements.

The prompt that will be issued for the term "Cancel" will be like:

```
You are a professional translator with expertise in mobile app localization. Please translate the following user interface string from English to French: "Cancel"

Please take into account the following translation context: This is the button title for cancelling an action and returning to the previous screen

Important instructions:

- Maintain all placeholders prefixed with "%" (e.g., %@, %lld, %lf) exactly as they appear
- Maintain any URLs or email addresses exactly as they appear
- Preserve any markdown tags and their contents, including the exact contents of links
- Do not output any HTML tags or other non-markdown styling
- Keep the same line breaks and formatting
- For buttons and short UI elements, prioritize concise translations
- Maintain the same tone and formality level as the source text
- There is no limit to the length of the response, so do not truncate any part of the response
```

### Refreshing translations

Once you have added one or more strings for a language, you can update any existing translations
with new strings without specifying the `--lang` parameter.

For example, if you add a new `Text("Items")` to the project and re-build,
you can then just run: 

```
translatrix --model codellama:34b-code SampleApp/Localizable.xcstrings
```

and any existing languages will have new entries translated.

Note that pre-existing translations will not be re-translated unless you
either specify `--force` (which re-translates everything), or `--retranslate <state>`.

For example, to cause all translations with the `needs_review` state to be retranslated
(for example, if you are trying out a new LLM to see if the translation improves),
you could run:

```
translatrix --model mistral --retranslate needs_review SampleApp/Localizable.xcstrings

Translating terms: ["Hello, world!"]
Re-translating fr state needs_review: 'Hello, world!': “Bonjour, le monde!”
Translating "Hello, world!" from English to French using mistral…
French (fr): Bonjour, Monde!

# compare the old and new translations
git diff
```


## License

GPL v3
