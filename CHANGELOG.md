# Changelog

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
