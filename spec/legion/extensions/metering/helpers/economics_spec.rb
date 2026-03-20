# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/metering/helpers/economics'

unless defined?(Sequel)
  module Sequel
    def self.lit(*args) = args
  end
end

RSpec.describe Legion::Extensions::Metering::Helpers::Economics do
  let(:economics_instance) { Class.new { include Legion::Extensions::Metering::Helpers::Economics }.new }

  before do
    stub_const('Legion::Data', Module.new do
      def self.connection
        @connection ||= Class.new do
          def [](_table)
            Class.new do
              def where(*_args, **_kwargs) = self
              def group_and_count(*_) = self
              def order(_) = self
              def limit(_) = self
              def select(*_) = self
              def all = []
              def sum(_col) = 0
              def count = 0
              def avg(_col) = 0
            end.new
          end
        end.new
      end
    end)
  end

  describe '#payroll_summary' do
    it 'returns a hash with workers array and total_cost' do
      result = economics_instance.payroll_summary(period: :daily)
      expect(result).to have_key(:workers)
      expect(result).to have_key(:total_cost)
      expect(result[:workers]).to be_an(Array)
    end
  end

  describe '#worker_report' do
    it 'returns a hash with salary and productivity' do
      result = economics_instance.worker_report(worker_id: 'w-1')
      expect(result).to have_key(:salary)
      expect(result).to have_key(:productivity)
    end
  end

  describe '#budget_forecast' do
    it 'returns projected cost for given days' do
      result = economics_instance.budget_forecast(days: 30)
      expect(result).to have_key(:projected_cost)
      expect(result).to have_key(:trend)
    end
  end
end
