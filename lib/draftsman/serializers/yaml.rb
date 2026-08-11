require 'yaml'

module Draftsman
  module Serializers
    module Yaml
      extend self # makes all instance methods become module methods as well

      # Classes Draftsman writes into its serialized columns. Named as strings
      # because this file loads before ActiveSupport autoloads them.
      PERMITTED_CLASS_NAMES = %w[
        ActiveSupport::TimeWithZone
        ActiveSupport::TimeZone
        BigDecimal
        Date
        DateTime
        Symbol
        Time
      ].freeze

      def load(string)
        YAML.load(string, permitted_classes: permitted_classes, aliases: true)
      end

      def dump(object)
        YAML.dump object
      end

      def permitted_classes
        draftsman_permitted_classes | Array(active_record_permitted_classes)
      end

      private

      def draftsman_permitted_classes
        PERMITTED_CLASS_NAMES.map do |name|
          begin
            Object.const_get(name)
          rescue NameError
            nil
          end
        end.compact
      end

      def active_record_permitted_classes
        ActiveRecord.yaml_column_permitted_classes
      end
    end
  end
end
