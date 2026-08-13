require 'draftsman/config'
require 'draftsman/model'

# Require all frameworks and serializers
Dir[File.join(File.dirname(__FILE__), 'draftsman', 'frameworks', '*.rb')].each { |file| require file }
Dir[File.join(File.dirname(__FILE__), 'draftsman', 'serializers', '*.rb')].each { |file| require file }

# Draftsman's module methods can be called in both models and controllers.
module Draftsman
  # Switches Draftsman on or off.
  def self.enabled=(value)
    Draftsman.config.enabled = value
  end

  # Returns `true` if Draftsman is on, `false` otherwise.
  # Draftsman is enabled by default.
  def self.enabled?
    !!Draftsman.config.enabled
  end

  # Draftsman's own deprecator. Rails 7.1 made the class-level
  # `ActiveSupport::Deprecation.warn` private, so gems own an instance.
  def self.deprecator
    @deprecator ||= ActiveSupport::Deprecation.new('1.0', 'Draftsman')
  end

  # Sets whether Draftsman is enabled or disabled for the current request.
  def self.enabled_for_controller=(value)
    draftsman_store[:request_enabled_for_controller] = value
  end

  # Returns `true` if Draftsman is enabled for the request, `false` otherwise.
  #
  # See `Draftsman::Rails::Controller#draftsman_enabled_for_controller`.
  def self.enabled_for_controller?
    !!draftsman_store[:request_enabled_for_controller]
  end

  # Returns whether `#save_draft` should record a draft right now. The
  # per-request switch is only consulted when a request has actually set it,
  # so drafting still works outside a request.
  def self.drafting_enabled?
    return false unless enabled?
    return enabled_for_controller? if draftsman_store.key?(:request_enabled_for_controller)
    true
  end

  # Returns any information from the controller that you want Draftsman to store.
  #
  # See `Draftsman::Controller#info_for_draftsman`.
  def self.controller_info
    draftsman_store[:controller_info]
  end

  # Sets any information from the controller that you want Draftsman to store. By default, this is set automatically by
  # a before filter.
  def self.controller_info=(value)
    draftsman_store[:controller_info] =  value
  end

  # Returns default class name used for drafts.
  def self.draft_class_name
    Draftsman.config.draft_class_name
  end

  # Sets default class name to use for drafts.
  def self.draft_class_name=(class_name)
    Draftsman.config.draft_class_name = class_name
  end

  # Set the field which records when a draft was created.
  def self.timestamp_field=(field_name)
    Draftsman.config.timestamp_field = field_name
  end

  # Returns the field which records when a draft was created.
  def self.timestamp_field
    Draftsman.config.timestamp_field
  end

  # Returns serializer to use for `object`, `object_changes`, and `previous_draft` columns.
  def self.serializer
    Draftsman.config.serializer
  end

  # Sets serializer to use for `object`, `object_changes`, and `previous_draft` columns.
  def self.serializer=(value)
    Draftsman.config.serializer = value
  end

  # Sets whether or not `#save_draft` should stash drafted changes into the
  # associated draft record or persist them to the main item.
  def self.stash_drafted_changes=(value)
    Draftsman.config.stash_drafted_changes = value
  end

  # Returns setting for whether or not `#save_draft` should stash drafted
  # changes into the associated draft record.
  def self.stash_drafted_changes?
    Draftsman.config.stash_drafted_changes?
  end

  # Returns who is reponsible for any changes that occur.
  def self.whodunnit
    draftsman_store[:whodunnit]
  end

  # Sets who is responsible for any changes that occur. You would normally use
  # this in a migration or on the console when working with models directly. In
  # a controller, it is set automatically to the `current_user`.
  def self.whodunnit=(value)
    draftsman_store[:whodunnit] = value
  end

  # Returns the field which records whodunnit data.
  def self.whodunnit_field
    Draftsman.config.whodunnit_field
  end

  # Sets global attribute name for `whodunnit` data.
  def self.whodunnit_field=(field_name)
    Draftsman.config.whodunnit_field = field_name
  end

  # Discards request-scoped data (`whodunnit`, `controller_info`, and the
  # per-request enabled flag). In Rails this runs around each execution so one
  # request cannot inherit another's values.
  def self.clear_store!
    draftsman_store.clear
  end

private

  # Per-execution store for request-scoped data. `Thread.current[]` is
  # fiber-local, so state set before a fiber or thread boundary is invisible
  # after it; Rails' own isolation level is `:thread`.
  def self.draftsman_store
    ActiveSupport::IsolatedExecutionState[:draftsman] ||= {}
  end

  # Returns Draftman's configuration object.
  def self.config
    @@config ||= Draftsman::Config.instance
  end

  def self.configure
    yield config
  end
end

# Draft model class.
require 'draftsman/draft'

# Inject `Draftsman::Model` into ActiveRecord classes.
ActiveSupport.on_load(:active_record) do
  include Draftsman::Model
end
