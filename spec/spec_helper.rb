# frozen_string_literal: true

require 'simplecov'
SimpleCov.start

require 'legion/logging'
require 'legion/settings'
require 'legion/json'
require 'legion/data'
require 'legion/cache'
require 'legion/crypt'
require 'legion/transport'

module Legion
  module Extensions
    module Core
    end

    module Helpers
      module Lex
        def self.included(base)
          base
        end
      end
    end

    module Actors
      class Every; end # rubocop:disable Lint/EmptyClass
    end
  end
end

$LOADED_FEATURES << 'legionio.rb'
$LOADED_FEATURES << 'legion/extensions/core.rb'
$LOADED_FEATURES << 'legion/extensions/actors/every'

lib = File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'legion/extensions/metering'

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
