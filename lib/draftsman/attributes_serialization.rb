module Draftsman
  module AttributesSerialization
    # Used for `Version#object` attribute.
    def serialize_attributes_for_draftsman(attributes)
      alter_attributes_for_draftsman(:serialize, attributes)
    end

    def unserialize_attributes_for_draftsman(attributes)
      alter_attributes_for_draftsman(:deserialize, attributes)
    end

    def alter_attributes_for_draftsman(serializer, attributes)
      # Don't serialize before values before inserting into columns of type
      # `JSON` on `PostgreSQL` databases.
      return attributes if self.draft_class.object_col_is_json?

      attributes.each do |key, value|
        attributes[key] = type_for_attribute(key).send(serializer, value)
      end
    end

    # Used for Version#object_changes attribute.
    def serialize_draft_attribute_changes(changes)
      alter_draft_attribute_changes(:serialize, changes)
    end

    def unserialize_draft_attribute_changes(changes)
      alter_draft_attribute_changes(:deserialize, changes)
    end

    def alter_draft_attribute_changes(serializer, changes)
      # Don't serialize before values before inserting into columns of type
      # `JSON` on `PostgreSQL` databases.
      return changes if self.draft_class.object_changes_col_is_json?

      changes.clone.each do |key, change|
        type = type_for_attribute(key)
        changes[key] = Array(change).map { |value| type.send(serializer, value) }
      end
    end
  end
end
