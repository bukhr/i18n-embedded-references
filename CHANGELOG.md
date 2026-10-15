# Changelog

## 1.3.0

- Transforms: `${key|upcase}` changes the case of the referenced text, and
  `${key|downcase|upcase_first}` chains them left to right. Available:
  `upcase`, `downcase`, `capitalize`, `upcase_first`, `downcase_first`.
  Interpolation placeholders (`%{name}`, `%<name>d`, `%%`) are kept verbatim
  so they still interpolate afterwards. An unknown transform name, or a
  transform on a reference whose value is not text (a hash, an array, a
  number, a boolean...), raises
  `I18n::Backend::EmbeddedReferences::TransformError` at runtime and is
  reported by the checker as a `transform` error. A pluralization hash is
  accepted: with `count` it resolves to one of its strings before the
  transform runs.
- `I18n::EmbeddedReferences::Syntax::Reference` carries the parsed
  `transforms` (an empty array when there are none) and exposes `marker`,
  the reference as written.

## 1.2.1

- Gem description mentions the static checker and describes the gem as a
  maintained alternative to i18n-recursive-lookup rather than its successor.
  No code changes.

## 1.2.0

- The requested locale is taken from the `fallback_original_locale` option
  that `I18n::Backend::Fallbacks` passes down, so references resolve with the
  right locale when Fallbacks is included above the backend (Rails includes
  it into the root backend class, a Chain in many apps). Requires i18n >= 1.9.
- Every reference in a translation resolves with the requested locale. Before,
  with an explicit `locale:` different from `I18n.locale`, only the first
  `${ref}` did and the rest fell back to `I18n.locale`. Thanks to @seff73 for
  reporting it and pinning the plain-backend case with a test (#3).
- Inside hashes and arrays a missing referenced key is handled per element
  by the standard exception handler instead of making the whole structure
  missing.
- `I18n.exists?` no longer resolves references, it only tells whether the
  key is defined. Before, a broken reference raised `UncaughtThrowError` and
  references resolved with `I18n.locale` instead of the given locale.
- `require 'i18n-embedded-references'` (Bundler's default autorequire for
  the gem name) now works; `require 'i18n/embedded_references'` stays valid.
- `rake i18n:embedded_references:check` boots the app when an `:environment`
  task exists and mirrors `I18n.fallbacks`, so Rails apps no longer need
  `--default-fallback`/`--fallback`. App chains are used verbatim, in their
  own order and without prepending the locale when the chain does not start
  with it, since that is exactly what the backend walks at runtime.
  Precedence is flags > config file > app: a locale configured there ignores
  the app chain and defaults. `APP_FALLBACKS=false` disables it. When the
  app's backend does not include `I18n::Backend::Fallbacks`, the task checks
  without fallbacks (no regional parent) and prints a warning naming the
  environment. New `IGNORE_MISSING` variable for the task.
- The checker and the backend share one grammar for `${key}`
  (`I18n::EmbeddedReferences::Syntax`), so they no longer disagree: the
  checker takes the key verbatim (`${ name }` is reported as broken, like the
  runtime treats it), only an exact `${key}` counts as a whole-string
  reference (`" ${menu}"` is a scope error), and references in hashes inside
  arrays are checked too.

## 1.1.0

- Static checker for locale files: `i18n-embedded-references check` (CLI),
  `rake i18n:embedded_references:check` (Rails railtie or manual require).
  Reports broken references honouring fallbacks, circular references and
  hash/array targets embedded in text. Config via `.i18n-embedded-references.yml`
  or flags (`--fallback`, `--default-fallback`, `--ignore-missing`, `--quiet`).

## 1.0.0

Initial release. A maintained alternative to [i18n-recursive-lookup](https://github.com/annkissam/i18n-recursive-lookup),
rewritten without ActiveSupport.

- `${key}` references inside strings, hashes and arrays, resolved recursively.
- `$${key}` escapes to the literal `${key}`.
- References resolve with the originally requested locale, so fallbacks and
  backend chains apply to the referenced key too.
- Circular references raise `I18n::Backend::EmbeddedReferences::CircularReferenceError`.
- `raise:` and `throw:` options propagate to referenced lookups.
- No write-back cache into the translation store.
