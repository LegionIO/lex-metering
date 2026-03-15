# frozen_string_literal: true

require 'legion/extensions/metering/version'

module Legion
  module Extensions
    module Metering
      extend Legion::Extensions::Core if Legion::Extensions.const_defined? :Core

      def self.data_required?
        true
      end

      def data_required?
        true
      end
    end
  end
end
