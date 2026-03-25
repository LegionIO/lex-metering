# frozen_string_literal: true

require 'legion/extensions/metering/version'
require 'legion/extensions/metering/runners/cost_optimizer'
require 'legion/extensions/metering/runners/rollup'

module Legion
  module Extensions
    module Metering
      extend Legion::Extensions::Core if Legion::Extensions.const_defined? :Core

      def self.data_required?
        false
      end

      def data_required?
        false
      end
    end
  end
end
