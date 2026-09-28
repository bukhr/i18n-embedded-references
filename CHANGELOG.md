# Changelog

## 1.2.0

- The requested locale is taken from the `fallback_original_locale` option
  that `I18n::Backend::Fallbacks` passes down, so references resolve with the
  right locale when Fallbacks is included above the backend (Rails includes
  it into the root backend class, a Chain in many apps). Requires i18n >= 1.9.
- Inside hashes and arrays a missing referenced key is handled per element
  by the standard exception handler instead of making the whole structure
  missing.
- `require 'i18n-embedded-references'` (Bundler's default autorequire for
  the gem name) now works; `require 'i18n/embedded_references'` stays valid.
- `rake i18n:embedded_references:check` boots the app when an `:environment`
  task exists and mirrors `I18n.fallbacks`, so Rails apps no longer need
  `--default-fallback`/`--fallback`. App chains are used in their own order.
  Precedence is flags > config file > app: a locale configured there ignores
  the app chain and defaults. `APP_FALLBACKS=false` disables it. When the
  app's backend does not include `I18n::Backend::Fallbacks`, the task checks
  without fallbacks (no regional parent) and prints a warning naming the
  environment. New `IGNORE_MISSING` variable for the task.

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
