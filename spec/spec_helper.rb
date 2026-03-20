# frozen_string_literal: true

require 'simplecov'
SimpleCov.start

module Legion
  module Logging
    def self.debug(_msg = nil); end
    def self.info(_msg = nil); end
    def self.warn(_msg = nil); end
    def self.error(_msg = nil); end
  end

  module Extensions
    module Core
    end
  end
end

$LOADED_FEATURES << 'legionio.rb'
$LOADED_FEATURES << 'legion/extensions/core.rb'

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
