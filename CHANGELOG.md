# Changelog

## 1.1.0

- Static checker for locale files: `i18n-embedded-references check` (CLI),
  `rake i18n:embedded_references:check` (Rails railtie or manual require).
  Reports broken references honouring fallbacks, circular references and
  hash/array targets embedded in text. Config via `.i18n-embedded-references.yml`
  or flags (`--fallback`, `--default-fallback`, `--ignore-missing`, `--quiet`).

## 1.0.0

Initial release. Successor of [i18n-recursive-lookup](https://github.com/annkissam/i18n-recursive-lookup),
rewritten without ActiveSupport.

- `${key}` references inside strings, hashes and arrays, resolved recursively.
- `$${key}` escapes to the literal `${key}`.
- References resolve with the originally requested locale, so fallbacks and
  backend chains apply to the referenced key too.
- Circular references raise `I18n::Backend::EmbeddedReferences::CircularReferenceError`.
- `raise:` and `throw:` options propagate to referenced lookups.
- No write-back cache into the translation store.
