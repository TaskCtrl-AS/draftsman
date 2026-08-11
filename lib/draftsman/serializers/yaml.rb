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
        if YAML.method(:load).parameters.any? { |_type, name| name == :permitted_classes }
          YAML.load(string, permitted_classes: permitted_classes, aliases: true)
        else
          YAML.load(string)
        end
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
        if ActiveRecord.respond_to?(:yaml_column_permitted_classes)
          # Rails 7.1+
          ActiveRecord.yaml_column_permitted_classes
        elsif ActiveRecord::Base.respond_to?(:yaml_column_permitted_classes)
          # Rails 7.0
          ActiveRecord::Base.yaml_column_permitted_classes
        else
          []
        end
      end
    end
  end
end
