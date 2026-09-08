# i18n-embedded-references

Reference other translations from inside a translation with `${key}`.

```yaml
en:
  company: Acme Corp
  welcome: "Welcome to ${company}"
  footer:
    legal: "${company} is a registered trademark."
```

```ruby
I18n.t(:welcome)        # => "Welcome to Acme Corp"
I18n.t(:'footer.legal') # => "Acme Corp is a registered trademark."
```

Change `company` once and every translation that embeds it follows.

This gem is the successor of [i18n-recursive-lookup](https://github.com/annkissam/i18n-recursive-lookup),
which has been unmaintained since 2015. It keeps the `${}` syntax, drops the
ActiveSupport dependency, resolves references recursively with cycle detection,
and is locale-aware when fallbacks are in play.

## Installation

```ruby
# Gemfile
gem 'i18n-embedded-references'
```

Then include the module in your backend. In Rails, for example in
`config/initializers/i18n.rb`:

```ruby
require 'i18n/embedded_references'

I18n::Backend::Simple.include(I18n::Backend::EmbeddedReferences)
```

If you also use `I18n::Backend::Fallbacks`, include `EmbeddedReferences` after
it so it wraps the whole fallback chain:

```ruby
class MyBackend < I18n::Backend::Simple
  include I18n::Backend::Fallbacks
  include I18n::Backend::EmbeddedReferences
end
```

Rails includes `Fallbacks` on its own when `config.i18n.fallbacks` is set; in
that case `I18n::Backend::Simple.include(I18n::Backend::EmbeddedReferences)`
from an initializer is enough.

## Syntax

| Written                | Result                                             |
|------------------------|----------------------------------------------------|
| `${some.key}`          | the value of `some.key`                            |
| `$${some.key}`         | the literal text `${some.key}`                     |
| `"${some.hash}"`       | the hash itself, when the string is only that ref  |
| `"${some.array}"`      | the array itself, when the string is only that ref |

References are resolved anywhere in the translation tree: in plain strings,
inside hashes returned by `I18n.t(:some_scope)`, and inside arrays.

## Semantics

**Recursive.** A referenced value may contain references of its own. A cycle
raises `I18n::Backend::EmbeddedReferences::CircularReferenceError`
with the full chain (`en.a -> en.b -> en.a`).

**Resolved before interpolation and pluralization.** Interpolation values and
`count` given to `I18n.t` are forwarded to referenced keys, so this works:

```yaml
en:
  body: "Dear %{name}"
  letter: "${body}, see you soon"
```

```ruby
I18n.t(:letter, name: 'Ann') # => "Dear Ann, see you soon"
```

**Locale-aware.** A reference is looked up with the locale that was originally
requested, not the locale where the referencing string was found. With
fallbacks `en-CL -> en`:

```yaml
en:
  name: notice
  alert: "alert ${name}"
en-CL:
  name: notice-cl
```

```ruby
I18n.t(:alert, locale: :'en-CL') # => "alert notice-cl"
```

`alert` comes from `en` via fallback, but `${name}` still prefers `en-CL`.
Explicit `locale:` options and `I18n::Backend::Chain` are honoured the same way.

**Missing references.** A missing referenced key makes the referencing
translation missing. Your usual `raise:`, `throw:` and exception handler apply,
and the message names the key that is actually absent
(`Translation missing: en.company`).

**No write-back.** Resolved values are never stored back into the translation
store, so `store_translations` at runtime is picked up on the next lookup and
the raw `${}` source is preserved in the backend.

## Checking references statically

The gem ships a checker that reads your locale files without booting the app
and reports, per file and key:

- **broken references**: the target key does not exist in the locale or its
  fallbacks (at runtime this would surface as a missing translation)
- **circular references**: `a -> b -> a` (at runtime: `CircularReferenceError`)
- **scope references embedded in text**: `"See ${menu}"` where `menu` is a
  hash or array

```bash
bundle exec i18n-embedded-references check config/locales packs/**/config/locales
```

```
config/locales/en.yml
  en.formulas.categories.sobretiempos.description
    error: broken reference ${{custom_translations.models.employee.one} (not found in en, es)

78 errors, 0 warnings, 21682 references checked in 19176 files (4.5s)
```

Exit status is 1 when there are errors, so it drops straight into CI.

Fallbacks default to the region-stripped parent (`es-CL` -> `es`). Anything
else, plus keys that another backend resolves at runtime, goes in
`.i18n-embedded-references.yml` (picked up automatically) or `--config FILE`:

```yaml
paths:
  - config/locales
  - packs/**/config/locales
default_fallbacks: [es]        # I18n.fallbacks = [:es]
fallbacks:
  ca: [es]                     # extra per-locale chains
ignore_missing:
  - 'custom_translations.*'    # resolved by a database backend, not YAML
```

The same options exist as flags: `--fallback ca:es`, `--default-fallback es`,
`--ignore-missing 'custom_translations.*'`, `--quiet`.

In Rails the task `rake i18n:embedded_references:check` is available
(`PATHS="a b"` and `CONFIG=file` override the config). Elsewhere, add
`require 'i18n/embedded_references/tasks'` to your Rakefile.

## Differences from i18n-recursive-lookup

- No ActiveSupport dependency.
- References resolve with the requested locale (see above); the original used
  the fallback locale, which returned the wrong value for locale overrides.
- No compiled-value cache written into the store. The original cached under the
  fallback locale, leaking locale-specific values across locales.
- Cycle detection instead of a stack overflow.
- Missing references surface through the standard I18n missing-translation
  handling instead of being spliced in as text.
- Interpolation values and `count` are forwarded to referenced keys.

## Development

```bash
bundle install
bundle exec rake test
bundle exec rubocop
```

## License

MIT. See [LICENSE](LICENSE).
