# frozen_string_literal: true

require_relative 'helper'

describe 'Sidekiq::Testing.inline' do
  class InlineError < RuntimeError; end
  class ParameterIsNotString < RuntimeError; end

  class InlineWorker
    include Sidekiq::Worker
    def perform(pass)
      raise ArgumentError, 'no jid' unless jid
      raise InlineError unless pass
    end
  end

  class InlineWorkerWithTimeParam
    include Sidekiq::Worker
    def perform(time)
      raise ParameterIsNotString unless time.is_a?(String) || time.is_a?(Numeric)
    end
  end

  before do
    require 'sidekiq/testing/inline'
    Sidekiq::Testing.inline!
  end

  after do
    Sidekiq::Testing.disable!
  end

  it 'stubs the async call when in testing mode' do
    assert InlineWorker.perform_async(true)

    assert_raises InlineError do
      InlineWorker.perform_async(false)
    end
  end

  describe 'delay' do
    require 'action_mailer'
    class InlineFooMailer < ActionMailer::Base
      def bar(_str)
        raise InlineError
      end
    end

    class InlineFooModel
      def self.bar(_str)
        raise InlineError
      end
    end

    before do
      Sidekiq::Extensions.enable_delay!
    end

    it 'stubs the delay call on mailers' do
      assert_raises InlineError do
        InlineFooMailer.delay.bar('three')
      end
    end

    it 'stubs the delay call on models' do
      assert_raises InlineError do
        InlineFooModel.delay.bar('three')
      end
    end
  end

  it 'stubs the enqueue call when in testing mode' do
    assert Sidekiq::Client.enqueue(InlineWorker, true)

    assert_raises InlineError do
      Sidekiq::Client.enqueue(InlineWorker, false)
    end
  end

  it 'stubs the push_bulk call when in testing mode' do
    assert Sidekiq::Client.push_bulk({ 'class' => InlineWorker, 'args' => [[true], [true]] })

    assert_raises InlineError do
      Sidekiq::Client.push_bulk({ 'class' => InlineWorker, 'args' => [[true], [false]] })
    end
  end

  it 'should relay parameters through json' do
    assert Sidekiq::Client.enqueue(InlineWorkerWithTimeParam, Time.now.to_f)
  end
end
