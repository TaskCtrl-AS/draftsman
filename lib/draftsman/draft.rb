class Draftsman::Draft < ActiveRecord::Base
  # Associations
  belongs_to :item, polymorphic: true

  # Validations
  validates :event, presence: true

  # Scopes
  # Returns `where` that filters to only `create` drafts.
  scope :creates,  -> { where(event: :create) }
  # Returns `where` that filters to only `destroy` drafts.
  scope :destroys, -> { where(event: :destroy) }
  # Returns `where` that filters to only `update` drafts.
  scope :updates,  -> { where(event: :update) }

  def self.with_item_keys(item_type, item_id)
    where(item_type: item_type, item_id: item_id)
  end

  # Reads an item's draft through its configured association name, which is not
  # always `draft`.
  def self.draft_for(item)
    item.send(item.class.draft_association_name)
  end

  # Returns whether the `object` column is using the `json` type supported by
  # PostgreSQL.
  def self.object_col_is_json?
    Draftsman.stash_drafted_changes? && draftsman_col_type('object') == :json
  end

  # Returns whether or not this class has an `object_changes` column.
  def self.object_changes_col_present?
    return @object_changes_col_present if defined?(@object_changes_col_present)
    @object_changes_col_present = column_names.include?('object_changes')
  end

  # Returns whether the `object_changes` column is using the `json` type
  # supported by PostgreSQL.
  def self.object_changes_col_is_json?
    draftsman_col_type('object_changes') == :json
  end

  # Returns whether the `previous_draft` column is using the `json` type supported by PostgreSQL.
  def self.previous_draft_col_is_json?
    draftsman_col_type('previous_draft') == :json
  end

  # Memoized column type lookup. `||=` would not cache a `nil` or `false`.
  def self.draftsman_col_type(name)
    @draftsman_col_types ||= {}
    return @draftsman_col_types[name] if @draftsman_col_types.key?(name)
    @draftsman_col_types[name] = columns_hash[name]&.type
  end

  # Returns what changed in this draft. Similar to `ActiveModel::Dirty#changes`.
  # Returns `nil` if your `drafts` table does not have an `object_changes` text
  # column.
  def changeset
    return nil unless self.class.object_changes_col_present?
    @changeset ||= load_changeset
  end

  # Returns whether or not this is a `create` event.
  def create?
    self.event == 'create'
  end

  # Returns whether or not this is a `destroy` event.
  def destroy?
    self.event == 'destroy'
  end

  # Returns related draft dependencies that would be along for the ride for a
  # `publish!` action.
  def draft_publication_dependencies
    dependencies = []

    my_item =
      if Draftsman.stash_drafted_changes? && self.item.draft?
        self.class.draft_for(self.item).reify
      else
        self.item
      end

    case self.event.to_sym
    when :create, :update
      associations = my_item.class.reflect_on_all_associations(:belongs_to)

      associations.each do |association|
        association_class =
          if association.options.key?(:polymorphic)
            my_item.send(association.foreign_key.sub('_id', '_type')).constantize
          else
            association.klass
          end

        if association_class.draftable? && association.name != association_class.draft_association_name.to_sym
          dependency = my_item.send(association.name)

          if dependency.present? && dependency.draft?
            dependency_draft = self.class.draft_for(dependency)
            dependencies << dependency_draft if dependency_draft.create?
          end
        end
      end
    when :destroy
      associations = my_item.class.reflect_on_all_associations(:has_one) + my_item.class.reflect_on_all_associations(:has_many)

      associations.each do |association|
        if association.klass.draftable?
          # Reconcile different association types into an array, even if `has_one` produces a single-item
          associated_dependencies =
            case association.macro
            when :has_one
              my_item.send(association.name).present? ? [my_item.send(association.name)] : []
            when :has_many
              my_item.send(association.name)
            end

          associated_dependencies.each do |dependency|
            dependencies << self.class.draft_for(dependency) if dependency.draft?
          end
        end
      end
    end

    dependencies
  end

  # Returns related draft dependencies that would be along for the ride for a
  # `revert!` action.
  def draft_reversion_dependencies
    dependencies = []

    case self.event.to_sym
    when :create
      associations = self.item.class.reflect_on_all_associations(:has_one) + self.item.class.reflect_on_all_associations(:has_many)

      associations.each do |association|
        if association.klass.draftable?
          # Reconcile different association types into an array, even if
          # `has_one` produces a single-item
          associated_dependencies =
            case association.macro
            when :has_one
              self.item.send(association.name).present? ? [self.item.send(association.name)] : []
            when :has_many
              self.item.send(association.name)
            end

          associated_dependencies.each do |dependency|
            dependencies << self.class.draft_for(dependency) if dependency.draft?
          end
        end
      end
    when :destroy
      associations = self.item.class.reflect_on_all_associations(:belongs_to)

      associations.each do |association|
        association_class =
          if association.options.key?(:polymorphic)
            self.item.send(association.foreign_key.sub('_id', '_type')).constantize
          else
            association.klass
          end

        if association_class.draftable? && association_class.trashable? && association.name != association_class.draft_association_name.to_sym
          dependency = self.item.send(association.name)
          if dependency.present? && dependency.draft?
            dependency_draft = self.class.draft_for(dependency)
            dependencies << dependency_draft if dependency_draft.destroy?
          end
        end
      end
    end

    dependencies
  end

  # Publishes this draft's associated `item`, publishes its `item`'s
  # dependencies, and destroys itself.
  # -  For `create` drafts, adds a value for the `published_at` timestamp on the
  #    item and destroys the draft.
  # -  For `update` drafts, applies the drafted changes to the item and destroys
  #    the draft.
  # -  For `destroy` drafts, destroys the item and the draft.
  #
  # Params:
  # -  A hash of options that get merged with `publish_options` defined in
  #    `has_drafts` and passed to `item.save`.
  def publish!(**options)
    publish_draft!(Set.new, **options)
  end

  # Publishes this draft, tracking which drafts have already been visited so a
  # dependency cycle terminates instead of recursing forever.
  def publish_draft!(visited, **options)
    return if visited.include?(self.id)
    visited << self.id

    ActiveRecord::Base.transaction do
      case self.event.to_sym
      when :create, :update
        # Parents must be published too
        self.draft_publication_dependencies.each { |dependency| dependency.publish_draft!(visited) }

        # Update drafts need to copy over data to main record
        self.item.attributes = self.reify.attributes if Draftsman.stash_drafted_changes? && self.update?

        # Write `published_at` attribute
        self.item.send("#{self.item.class.published_at_attribute_name}=", current_time_from_proper_timezone)

        # Clear out draft
        self.item.send("#{self.item.class.draft_association_name}_id=", nil)

        self.item.save(**self.item.draftsman_options[:publish_options].merge(options))
        self.item.reload

        # Destroy draft
        self.destroy
      when :destroy
        self.item.destroy
      end
    end
  end

  # Returns instance of item converted to its drafted state.
  #
  # Example usage:
  #
  #     `@category = @category.draft.reify if @category.draft?`
  def reify
    # This appears to be necessary if for some reason the draft's model
    # hasn't been loaded (such as when done in the console).
    unless defined? self.item_type
      require self.item_type.underscore
    end

    # Create draft doesn't require reification.
    if self.create?
      self.item
    # If a previous draft is stashed, restore that.
    elsif self.previous_draft.present?
      reify_previous_draft.reify
    # Prefer changeset for refication if it's present.
    elsif self.changeset.present? && self.changeset.any?
      self.changeset.each do |key, value|
        next if counter_cache_columns.include?(key)

        if self.item.respond_to?("#{key}=")
          self.item.send("#{key}=", value.last)
        else
          logger&.warn("Attribute #{key} does not exist on #{self.item_type} (Draft ID: #{self.id}).")
        end
      end

      self.item.send("#{self.item.class.draft_association_name}=", self)
      self.item
    # Reify based on object if it's all that's available.
    elsif self.object.present?
      attrs = self.class.object_col_is_json? ? self.object : Draftsman.serializer.load(self.object)
      self.item.class.unserialize_attributes_for_draftsman(attrs)

      attrs.each do |key, value|
        next if counter_cache_columns.include?(key)

        if self.item.respond_to?("#{key}=")
          self.item.send("#{key}=", value)
        else
          logger&.warn("Attribute #{key} does not exist on #{self.item_type} (Draft ID: #{self.id}).")
        end
      end

      self.item.send("#{self.item.class.draft_association_name}=", self)
      self.item
    end
  end

  # Reverts this draft.
  # -  For create drafts, destroys the draft and the item.
  # -  For update drafts, destroys the draft only.
  # -  For destroy drafts, destroys the draft and undoes the `trashed_at`
  #    timestamp on the item. If a previous draft was drafted for destroy,
  #    restores the draft.
  def revert!
    revert_draft!(Set.new)
  end

  # Reverts this draft, tracking which drafts have already been visited so a
  # dependency cycle terminates instead of recursing forever.
  def revert_draft!(visited)
    return if visited.include?(self.id)
    visited << self.id

    ActiveRecord::Base.transaction do
      case self.event.to_sym
      when :create
        self.item.destroy
        self.destroy
      when :update
        # If we're not stashing changes, we need to restore original values from
        # the changeset.
        if self.class.object_changes_col_present? && !Draftsman.stash_drafted_changes?
          self.changeset.each do |attr, values|
            self.item.send("#{attr}=", values.first) if self.item.respond_to?(attr)
          end
        end
        # Then clear out the draft ID.
        self.item.send("#{self.item.class.draft_association_name}_id=", nil)
        self.item.save!(validate: false, touch: false)
        # Then destroy draft.
        self.destroy
      when :destroy
        # Parents must be restored too
        self.draft_reversion_dependencies.each { |dependency| dependency.revert_draft!(visited) }

        # Restore previous draft if one was stashed away
        if self.previous_draft.present?
          prev_draft = reify_previous_draft
          prev_draft.save!

          self.item.class.where(id: self.item).update_all "#{self.item.class.draft_association_name}_id".to_sym => prev_draft.id,
                                                          self.item.class.trashed_at_attribute_name => nil
        else
          self.item.class.where(id: self.item).update_all "#{self.item.class.draft_association_name}_id".to_sym => nil,
                                                          self.item.class.trashed_at_attribute_name => nil
        end

        self.destroy
      end
    end
  end

  # Returns whether or not this is an `update` event.
  def update?
    self.event.to_sym == :update
  end

private

  # Columns ActiveRecord maintains via `counter_cache`. Reifying them from
  # drafted data would clobber the live count.
  def counter_cache_columns
    @counter_cache_columns ||=
      self.item.class.reflect_on_all_associations(:has_many).map do |reflection|
        begin
          reflection.counter_cache_column.to_s if reflection.has_cached_counter?
        rescue StandardError
          nil
        end
      end.compact
  end

  # Restores previous draft and returns it.
  def reify_previous_draft
    draft = self.class.new

    attrs = self.class.object_col_is_json? ? self.previous_draft : Draftsman.serializer.load(self.previous_draft)

    attrs.each do |key, value|
      if key.to_sym != :id && draft.respond_to?("#{key}=")
        draft.send("#{key}=", value)
      elsif key.to_sym != :id
        logger.warn("Attribute #{key} does not exist on #{item_type} (Draft ID: #{self.id}).")
      end
    end

    draft
  end

  def load_changeset
    return {} if self.object_changes.blank?

    changes = ActiveSupport::HashWithIndifferentAccess.new(object_changes_deserialized)
    self.item_type.constantize.unserialize_draft_attribute_changes(changes)
    changes
  end

  def object_changes_deserialized
    if self.class.object_changes_col_is_json?
      self.object_changes
    else
      Draftsman.serializer.load(self.object_changes)
    end
  end
end
