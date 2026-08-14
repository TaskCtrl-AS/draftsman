# CHANGELOG

## Unreleased

Maintained fork at [TaskCtrl-AS/draftsman](https://github.com/TaskCtrl-AS/draftsman).
Not published to RubyGems; install from git.

### Breaking Changes

- Requires ActiveRecord 7.1+ and Ruby 3.2+. The gemspec previously claimed
  ActiveRecord 4.2+, but that range was untestable — 4.2 through 6.1 need
  Ruby 2.x — so nothing verified it. The floor now matches what CI runs.
  ([#10](https://github.com/TaskCtrl-AS/draftsman/pull/10))
- Removed the compatibility shims that became unreachable at that floor:
  `Draftsman.active_record_belongs_to_required?`,
  `Draftsman.active_record_protected_attributes?`, `lib/support/feature_detection.rb`
  (which also defined `activerecord_migrations_versioned?` on `Object`), the
  pre-5.0 `SERIALIZE`/`DESERIALIZE` indirection,
  `Draftsman::AttributesSerialization::NoOpAttribute` and `SerializedAttribute`,
  and `without_identity_map`. ([#10](https://github.com/TaskCtrl-AS/draftsman/pull/10))

### Bug Fixes

- `Draft#reify` raised `Psych::DisallowedClass` and `Draft#changeset` silently
  returned `{}` on Rails 7.0.3.1+. `ActiveRecord.yaml_column_permitted_classes`
  defaults to `[Symbol]`, but Draftsman writes timestamps and numerics into its
  serialized columns, so it could not read back its own output. The YAML
  serializer now permits the classes it writes, unioned with any the host app
  has configured. ([#2](https://github.com/TaskCtrl-AS/draftsman/pull/2))
- `#save_draft` returned `true` when the draft record failed to save.
  `raise ActiveRecord::Rollback and return false` parses as
  `(raise …) and (return false)`, so the raise aborted, `transaction` swallowed
  the rollback, and control reached an unconditional `return true`. The item was
  rolled back out of the database while the caller was told it succeeded.
  ([#2](https://github.com/TaskCtrl-AS/draftsman/pull/2))
- `#save_draft` rescued `Exception`, swallowing `Interrupt`, `SystemExit`, and
  `NoMemoryError`. Narrowed to `StandardError`.
  ([#2](https://github.com/TaskCtrl-AS/draftsman/pull/2))
- `Draft#changeset` swallowed every error and returned `{}`, making an
  unreadable draft indistinguishable from one that changed nothing.
  ([#2](https://github.com/TaskCtrl-AS/draftsman/pull/2))
- `Draftsman::Draft.with_item_keys` called `scoped`, removed in Rails 4, and had
  raised `NoMethodError` on every call since.
  ([#2](https://github.com/TaskCtrl-AS/draftsman/pull/2))
- `has_drafts draft: :custom_name` was broken in six places that read
  `item.draft` directly instead of going through the configured association
  name. The guard immediately before each (`item.draft?`) used the configured
  name correctly, so the check passed and the next line raised `NoMethodError` —
  which `_draft_update` then swallowed, silently discarding the edit.
  ([#4](https://github.com/TaskCtrl-AS/draftsman/pull/4),
  [#6](https://github.com/TaskCtrl-AS/draftsman/pull/6))
- `Draftsman.draft_class_name` is global configuration but was stored in
  fiber-local state. Since `has_drafts` reads it at class-definition time, a
  model autoloaded lazily on a worker thread — the Rails development default —
  bound to `Draftsman::Draft` instead of the configured class. Moved to
  `Draftsman::Config`. ([#5](https://github.com/TaskCtrl-AS/draftsman/pull/5))
- `whodunnit` and `controller_info` were stored in `Thread.current[]`, which is
  fiber-local, so state set by a controller filter was invisible inside any
  fiber. Now uses `ActiveSupport::IsolatedExecutionState`.
  ([#5](https://github.com/TaskCtrl-AS/draftsman/pull/5))
- Request-scoped state was never cleared, so a pooled thread carried one
  request's `whodunnit` into the next request that did not set its own,
  attributing drafts to the wrong user. A Railtie now clears it around each
  execution, which covers requests and background jobs.
  ([#7](https://github.com/TaskCtrl-AS/draftsman/pull/7))
- `Draft#publish!` and `Draft#revert!` recursed until `SystemStackError` when
  two records with drafts referenced each other. Both now track visited drafts.
  ([#6](https://github.com/TaskCtrl-AS/draftsman/pull/6))
- `#draft_creation`, `#draft_update`, and `#draft_destroy` raised
  `NoMethodError` on Rails 7.1+, where the class-level
  `ActiveSupport::Deprecation.warn` became private. The deprecation shim was the
  thing that broke. Draftsman now owns a deprecator instance.
  ([#9](https://github.com/TaskCtrl-AS/draftsman/pull/9))
- `rails g draftsman:install` hardcoded `ActiveRecord::Migration[4.2]`, opting
  new installs into a legacy compatibility mode that gives `drafts` a 32-bit
  primary key. The version is now taken from the installed ActiveRecord, and
  `item_id` is `bigint` rather than `integer`.
  ([#8](https://github.com/TaskCtrl-AS/draftsman/pull/8))
- `Draftsman.enabled = false` did not stop drafting. Neither `enabled?` nor
  `enabled_for_controller?` was consulted anywhere in the draft-writing path;
  their only reader was `set_draftsman_whodunnit`, so disabling Draftsman merely
  stopped recording who made the change. `#save_draft` now persists the record
  without recording a draft when drafting is disabled. `#draft_destruction` is
  unchanged and still trashes and drafts.
  ([#11](https://github.com/TaskCtrl-AS/draftsman/pull/11))
- `Draft#reify` skipped any attribute whose name ends in `_count`, intending to
  protect `counter_cache` columns but also silently dropping ordinary ones such
  as `word_count` or `view_count`. The draft stored the change and reported it in
  the changeset, then publishing discarded it. Counter caches are now identified
  through ActiveRecord's reflections instead of by name.
  ([#12](https://github.com/TaskCtrl-AS/draftsman/pull/12))
- `Draft#changeset` raised on unreadable stored data, so one bad row could abort
  a caller iterating drafts. Unreadable data is now logged and reported as `{}`,
  while genuine errors still propagate.
  ([#13](https://github.com/TaskCtrl-AS/draftsman/pull/13))

### Enhancements

- The test suite runs again. It could not boot at all: `File.exists?` was removed
  in Ruby 3.4, the dummy app pulled in Sinatra 1.0 via `Bundler.require` (which
  needs `rack/showexceptions`, gone in Rack 3), `sqlite3 ~> 1.2` conflicted with
  the Rails 8 adapter, and `enum status: {…}` was removed in Rails 8.
  ([#2](https://github.com/TaskCtrl-AS/draftsman/pull/2))
- CI moved from Travis and CircleCI 1.0 to GitHub Actions, covering ActiveRecord
  7.1, 7.2, and 8.0 across Ruby 3.2, 3.3, and 3.4.
  ([#2](https://github.com/TaskCtrl-AS/draftsman/pull/2))
- README rewritten to match reality: it advertised ActiveRecord 4/5/6 support,
  told people to install a RubyGems release that does not exist for this fork,
  carried a dead Travis badge, and claimed both thread safety and automatic
  `whodunnit` recording that the code did not provide.
  ([#14](https://github.com/TaskCtrl-AS/draftsman/pull/14))
- The three `*_col_is_json?` predicates memoized with `||=`, which never caches
  a `false` result, so they re-scanned `columns_hash` on every call from inside
  per-attribute loops. Column types are now cached.
  ([#4](https://github.com/TaskCtrl-AS/draftsman/pull/4))

## 0.8.0.dev

### Breaking Changes

- Now only supports ActiveRecord 4.2+.

### Enhancements

- [@iggant](https://github.com/iggant)
  [implemented](https://github.com/jmfederico/draftsman/pull/80/commits/74e290d895b272b45a4b611403afa5d554955938)
  [#67](https://github.com/jmfederico/draftsman/pull/80)
  ActiveRecord 5.2 compatibility

### Enhancements

- [@Looooong](https://github.com/Looooong)
  [implemented](https://github.com/jmfederico/draftsman/commit/181e3599aba9f9d6c76a3f37e65837cefababbb3)
  [#76](https://github.com/jmfederico/draftsman/pull/76)
  Options passed to `#save` when publishing a draft can now be customized.

## 0.7.1 - December 24, 2017

### Bug Fixes

- [@jmfederico](https://github.com/jmfederico)
  [fixed](https://github.com/jmfederico/draftsman/commit/ff46e510c7d82331fcad7ea1eb2d2d2728ed1bd5)
  [#73](https://github.com/jmfederico/draftsman/issues/73)
  Rails 5 migration error


## 0.7.0 - June 12, 2017

### Enhancements

- [@jmfederico](https://github.com/jmfederico)
  [implemented](https://github.com/liveeditor/draftsman/commit/87f242374ad9fd97f7dba2e485d68da407c46fed)
  [#67](https://github.com/liveeditor/draftsman/pull/67)
  5.1 compatibility
- [@chrisdpeters](https://github.com/chrisdpeters)
  [implemented](https://github.com/liveeditor/draftsman/commit/e2c8e497899a453daf4c60d6ce02cacbf15a0f12)
  Change Draft.object_col_is_json? to skip over itself if not stashing drafted changes
- [@npezza93](https://github.com/npezza93)
  [implemented](https://github.com/liveeditor/draftsman/commit/936d5a37c044c5ca0a5699a553d9bc111f2d91d2)
  [#58](https://github.com/liveeditor/draftsman/pull/58)
  Only update attributes that get changed instead of all of them
- [@jmfederico](https://github.com/jmfederico)
  [implemented](https://github.com/liveeditor/draftsman/commit/e8ba201db6bb88ea0ebc47c1262eb24e892e9a0b)
  [#65](https://github.com/liveeditor/draftsman/pull/65)
  Do not "touch" models when not updating the base table content

### Bug Fixes

- [@jokius](https://github.com/jokius)
  [fixed](https://github.com/liveeditor/draftsman/commit/5ca7d6717109d753959a5d56c0fe81c3cd7b75f1)
  [#57](https://github.com/liveeditor/draftsman/pull/57)
  Fix if self.changeset is nil
- [@jmfederico](https://github.com/jmfederico)
  [fixed](https://github.com/liveeditor/draftsman/commit/207d158d054ed13ca6dc0a15ae2c499b0aac5f5f)
  [#64](https://github.com/liveeditor/draftsman/pull/64)
  Fix error when saving a draft when one already existed

## 0.6.0 - November 16, 2016

### Enhancements

- [@chrisdpeters](https://github.com/chrisdpeters)
  [implemented](https://github.com/liveeditor/draftsman/commit/39e74ef34f34de83262761a383e94a7e7731d47f)
  [#53](https://github.com/liveeditor/draftsman/issues/53) -
  Add option to not stash drafted data separately
- [@chrisdpeters](https://github.com/chrisdpeters)
  [implemented](https://github.com/liveeditor/draftsman/commit/340e632b9590ae3a07f5b567df3ca2b6d9a5b804)
  [#31](https://github.com/liveeditor/draftsman/issues/51) -
  Allow `whodunnit` column name to be configurable
- [@chrisdpeters](https://github.com/chrisdpeters)
  [implemented](https://github.com/liveeditor/draftsman/commit/340e632b9590ae3a07f5b567df3ca2b6d9a5b804)
  [#51](https://github.com/liveeditor/draftsman/issues/51) -
  Performance: skip reification logic on create drafts
- [@chrisdpeters](https://github.com/chrisdpeters)
  [implemented](https://github.com/liveeditor/draftsman/commit/eae59a6991d9aef18a9f9a811ccc7a8668cd351f)
  [#47](https://github.com/liveeditor/draftsman/issues/47) -
  Add ``#save_draft` method to classes initialized with ``#has_drafts`

### Bug Fixes

- [@chrisdpeters](https://github.com/chrisdpeters)
  [fixed](https://github.com/liveeditor/draftsman/commit/696caf78baff938ebdf98c2867f6c4d2610b4611)
  [#49](https://github.com/liveeditor/draftsman/issues/49) -
  irb: warn: can't alias context from irb_context

### Deprecations/Breaking Changes

- Now only supports ActiveRecord 4+.
- `#draft_creation` and `#draft_update` are now deprecated and will be removed
  in v1.0.0. Use `#save_draft` instead.

## 0.5.1 - August 20, 2016

- [@chrisdpeters](https://github.com/chrisdpeters)
  [Fixed](https://github.com/liveeditor/draftsman/commit/b19efe6abf73b2e62a420df2aef39dc9eabf20dc)
  Make Draftsman enabled in Rails by default

## 0.5.0 - August 20, 2016

- [@npezza93](https://github.com/npezza93)
  [Implemented](https://github.com/liveeditor/draftsman/pull/45)
  [#44](https://github.com/liveeditor/draftsman/issues/44)
  Rails 5 compatibility

## 0.4.0 - April 5, 2016

- [@npafundi](https://github.com/npafundi)
  [Implemented](https://github.com/liveeditor/draftsman/pull/20)
  [#20](https://github.com/liveeditor/draftsman/pull/20) -
  Adding callbacks for draft creation, update, and destroy
- [@chrisdpeters](https://github.com/chrisdpeters)
  [Implemented](https://github.com/liveeditor/draftsman/commit/b3cecfa17f5cf296e7451cca56aeee41eac75f11)
  [#16](https://github.com/liveeditor/draftsman/issues/16) -
  Rename `draft_destroy` to `draft_destruction`
- [@defbyte](https://github.com/defbyte)
  [Fixed](https://github.com/liveeditor/draftsman/pull/38)
  [#39](https://github.com/liveeditor/draftsman/issues/39) -
  Uh oh, ActiveSupport::DeprecationException error when running generated migrations
- [@chrisdpeters](https://github.com/chrisdpeters)
  [Fixed](https://github.com/liveeditor/draftsman/commit/b0e328276e1e90ab877a6003f1d3165c7032267d)
  [#40](https://github.com/liveeditor/draftsman/issues/40) -
  Docs say publish! is available on the model instance, but it is not
- [@chrisdpeters](https://github.com/chrisdpeters)
  [Fixed](https://github.com/liveeditor/draftsman/commit/bae427d2d38715da5b892888ff86d23bf5e39cb0)
  [#17](https://github.com/liveeditor/draftsman/issues/17) -
  Fix "open-ended dependency on rake" warning on gem build

## 0.3.7 - November 4, 2015

- [@bdunham](https://github.com/bdunham)
  [Fixed](https://github.com/liveeditor/draftsman/commit/3610087a319fd203684146bb1d37bf0e41276743) -
  Prevented double require of model definition
- [@chrisdpeters](https://github.com/chrisdpeters)
  [Fixed](https://github.com/liveeditor/draftsman/commit/ec2edf45700a3bea8cfac6f9facbc8ef6c7f9f54)
  [#36](https://github.com/liveeditor/draftsman/issues/36) -
  Fails miserably with foreign keys
- [@dpaluy](https://github.com/dpaluy)
  [Fixed](https://github.com/dpaluy/draftsman/blob/afce35b3985c79760176f31710c11a77b1201f0e/config/initializers/draftsman.rb)
  [#33](https://github.com/liveeditor/draftsman/issues/33) -
  SerializedAttributes is deprecated in Rails 4.2.x, and will be removed in Rails 5
- [@chrisdpeters](https://github.com/chrisdpeters)
  [Fixed](https://github.com/liveeditor/draftsman/commit/adc2843105e8fcf34d714557e82cf3f24942dbcb) -
  Fix `serve_static_assets` deprecation warning

## 0.3.6 - August 16, 2015

- [@chrisdpeters](https://github.com/chrisdpeters)
  [Fixed](https://github.com/liveeditor/draftsman/commit/971b3d945e9190fbb103acac09c9d006db7a2a31) -
  Fix loading of Rails controller module for Rails 4.2+

## 0.3.5 - July 12, 2015

- [@npafundi](https://github.com/npafundi)
  [Fixed](https://github.com/liveeditor/draftsman/pull/29)
  [#28](https://github.com/liveeditor/draftsman/issues/28) -
  Skipped attributes aren't updated if a model has a draft

## 0.3.4 - May 21, 2015

- [@npafundi](https://github.com/npafundi)
  [Fixed](https://github.com/liveeditor/draftsman/pull/21)
  [#13](https://github.com/liveeditor/draftsman/issues/13) -
  LoadError when trying to run migrations
- [@npafundi](https://github.com/npafundi)
  [Fixed](https://github.com/liveeditor/draftsman/pull/23)
  [#22](https://github.com/liveeditor/draftsman/issues/22) -
  Exception on draft_destroy when has_one association is nil
- [@chrisdpeters](https://github.com/chrisdpeters)
  [Fixed](https://github.com/liveeditor/draftsman/commit/32b13375f4e50bafc3b4516d731d2fcf51a5fb2b)
  [#24](https://github.com/liveeditor/draftsman/issues/24) -
  Stack too deep: Error when running `bundle exec rails c` in app including draftsman

## 0.3.3 - April 8, 2015

-  Fixed regression [#18](https://github.com/liveeditor/draftsman/pull/19) - Exception when destroying drafts

## 0.3.2 - April 6, 2015

-  Fixed [#8](https://github.com/liveeditor/draftsman/issues/8) - Update specs to use new community standards
-  Fixed [#9](https://github.com/liveeditor/draftsman/issues/9) - Sinatra extension should not use Sinatra base namespace
-  Fixed [#12](https://github.com/liveeditor/draftsman/issues/12) - JSON::ParserError when draft_destroying a widget which was just created

## 0.3.1 - August 14, 2014

-  Commit [aae737f](https://github.com/live-editor/draftsman/commit/aae737fcdf48604bc480b1c9c141bf642c0f581c) - `skip` option not persisting skipped values correctly

## 0.3.0 - July 29, 2014

-  Commit [1e2a59f](https://github.com/live-editor/draftsman/commit/1e2a59f678cc4d88222dfc1976d564b5649cd329) - Add support for PostgreSQL JSON data type for `object`, `object_changes`, and `previous_draft` columns.

## v0.2.1 - June 28, 2014

-  Commit [dbc6c83](https://github.com/live-editor/draftsman/commit/dbc6c83abbea5211f67ad883f4a2d18a9f5ac181) - Reifying a record that was drafted for destruction uses data from a drafted update before that if that's what happened.

## v0.2.0 - June 3, 2014

-  Fixed [#4](https://github.com/live-editor/draftsman/issues/4) - Added `referenced_table_name` argument to scopes.

## v0.1.1 - March 7, 2014

-  Fixed [#3](https://github.com/minimalorange/draftsman/issues/3) - draft_publication_dependencies not honoring drafts
   when draft is an update.
-  Fixed [#1](https://github.com/minimalorange/draftsman/issues/1) - License missing from gemspec - Added MIT license.

## v0.1.0 - November 19, 2013

-  Initial release.
