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

This gem is a maintained alternative to [i18n-recursive-lookup](https://github.com/annkissam/i18n-recursive-lookup),
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

It works with `I18n::Backend::Fallbacks` wherever that is included: on the
same backend, or on a `Chain` above it (which is what Rails does with
`config.i18n.fallbacks`, so the initializer line above is all Rails needs).
Requires i18n >= 1.9.

## Syntax

| Written                | Result                                             |
|------------------------|----------------------------------------------------|
| `${some.key}`          | the value of `some.key`                            |
| `${some.key\|upcase}`  | the value of `some.key`, transformed (see below)   |
| `$${some.key}`         | the literal text `${some.key}`                     |
| `"${some.hash}"`       | the hash itself, when the string is only that ref  |
| `"${some.array}"`      | the array itself, when the string is only that ref |

The key is taken verbatim: `${ some.key }` refers to `" some.key "`, not to
`some.key`. Only an exact `"${some.hash}"` returns the structure; with any
text around it, whitespace included, the value is spliced into a string.

### Transforms

A reference may change the case of the text it pulls in, which saves keeping
a lowercase or capitalized copy of every noun that appears mid-sentence and
at the start of one:

```yaml
es:
  employee: colaborador
  found: "Se encontró un ${employee}"
  title: "${employee|upcase_first} encontrado"
  heading: "${employee|upcase}"
```

| Transform        | `jefe de Área` becomes |
|------------------|------------------------|
| `upcase`         | `JEFE DE ÁREA`         |
| `downcase`       | `jefe de área`         |
| `capitalize`     | `Jefe de área`         |
| `upcase_first`   | `Jefe de Área`         |
| `downcase_first` | `jefe de Área`         |

Transforms chain left to right: `${employee|downcase|upcase_first}`. They
apply once the reference is fully resolved, so nested references are expanded
first. Interpolation placeholders (`%{name}`, `%<count>d`, `%%`) are kept as
they are, so `${body|upcase}` with `body: "Dear %{name}"` gives
`DEAR %{name}` and still interpolates. When interpolation values are passed to
`I18n.t` they are forwarded to the referenced key before the transform, so the
interpolated text is transformed along with the rest.

Transform names are taken verbatim too. An unknown name, or a transform on a
reference whose value is not text (a hash, an array, a number, a boolean),
raises `I18n::Backend::EmbeddedReferences::TransformError`: both are mistakes
in the locale files, and the checker below reports them before they reach
runtime. A pluralization hash is the one structure that works: with `count`,
I18n picks one of its strings before the transform runs, so
`"${items|upcase}"` with `items: { one: ..., other: ... }` gives `2 ITEMS`
for `I18n.t(:label, count: 2)` (and raises without `count`).

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
string translation missing. Your usual `raise:`, `throw:` and exception handler
apply, and the message names the key that is actually absent
(`Translation missing: en.company`). Inside a hash or array (`I18n.t(:scope)`)
each element is resolved on its own, so a broken reference in one value does
not take the whole structure down.

**`I18n.exists?` does not resolve references.** It tells whether the key is
defined, the same way it ignores `%{}` placeholders, so a translation with a
broken reference still exists. Use `I18n.t` or the checker below to find
broken references.

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
- **transform errors**: `${name|shout}` names a transform that does not
  exist, or `${menu|upcase}` transforms something that is not text (a hash,
  an array, a number...; at runtime: `TransformError`). Pluralization hashes
  are accepted, since they resolve to text when `count` is given

```bash
bundle exec i18n-embedded-references check config/locales packs/**/config/locales
```

```
config/locales/en.yml
  en.footer.legal
    error: broken reference ${company_name} (not found in en)
  en.nav.label
    error: reference ${menu} is embedded in text but points to a hash or array

config/locales/es-CL.yml
  es-CL.welcome
    error: broken reference ${compnay} (not found in es-CL, es)

3 errors, 0 warnings, 142 references checked in 12 files (0.1s)
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

In Rails, prefer the rake task: it boots the app and reads `I18n.fallbacks`,
so the checker follows the same fallback chains as runtime without repeating
them as flags:

```bash
bin/rake i18n:embedded_references:check \
  PATHS="config/locales packs/**/config/locales" \
  IGNORE_MISSING="custom_translations.*"
```

```
Using fallbacks from I18n.fallbacks (4 locales, defaults: es)
3 errors, 0 warnings, 142 references checked in 12 files (1.8s)
```

Fallbacks are only taken from the app when its backend actually includes
`I18n::Backend::Fallbacks` (what `config.i18n.fallbacks` does). Each app chain
(`I18n.fallbacks[locale]`) is exactly what the backend walks at runtime, so it
is used verbatim: in its own order, without inserting the regional parent, and
without prepending the locale if the chain does not start with it (a custom
fallbacks object may return `[:en]` for `:pt`). Precedence is flags >
config file > app: a locale given in `fallbacks` (config or `CONFIG=file`)
ignores the app chain and the app defaults, and the app defaults only apply to
locales without an app chain. `APP_FALLBACKS=false` skips booting the app. Keys resolved by another backend still have to be listed in
`IGNORE_MISSING` (space separated globs): there is no way to infer them.
Outside Rails, add `require 'i18n/embedded_references/tasks'` to your Rakefile.

When the booted app does not use `I18n::Backend::Fallbacks`, the task checks
without fallbacks (no regional parent either, only the ones given by flags or
config) and says so:

```
App backend does not use I18n::Backend::Fallbacks (RAILS_ENV=test): checking without fallbacks
```

Mind the environment: Rails generates `production.rb` with
`config.i18n.fallbacks = true`, but development and test leave it off, and the
task usually runs in CI with `RAILS_ENV=test`. If production uses fallbacks and
test does not, the task reports references that production resolves. Align
`config.i18n.fallbacks` in test with production, or pass the fallbacks as
flags or config.

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

To release, bump `VERSION` in `lib/i18n/embedded_references/version.rb`, add
the entry to `CHANGELOG.md`, merge, and push a tag with the same version:

```bash
git tag v1.2.0 && git push origin v1.2.0
```

The `Release` workflow checks that the tag matches the version, runs the
tests and publishes to RubyGems.org through trusted publishing.

## License

MIT. See [LICENSE](LICENSE).
