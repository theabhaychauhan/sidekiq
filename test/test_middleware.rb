# frozen_string_literal: true

require_relative 'helper'
require 'sidekiq/middleware/chain'
require 'sidekiq/processor'

describe Sidekiq::Middleware do
  before do
    $errors = []
  end

  class CustomMiddleware
    def initialize(name, recorder)
      @name = name
      @recorder = recorder
    end

    def call(*_args)
      @recorder << [@name, 'before']
      yield
      @recorder << [@name, 'after']
    end
  end

  it 'supports custom middleware' do
    chain = Sidekiq::Middleware::Chain.new
    chain.add CustomMiddleware, 1, []

    assert_equal CustomMiddleware, chain.entries.last.klass
  end

  class CustomWorker
    $recorder = []
    include Sidekiq::Worker
    def perform(_recorder)
      $recorder << ['work_performed']
    end
  end

  class NonYieldingMiddleware
    def call(*args); end
  end

  class ArgumentYieldingMiddleware
    def call(*_args)
      yield 1
    end
  end

  class AnotherCustomMiddleware
    def initialize(name, recorder)
      @name = name
      @recorder = recorder
    end

    def call(*_args)
      @recorder << [@name, 'before']
      yield
      @recorder << [@name, 'after']
    end
  end

  class YetAnotherCustomMiddleware
    def initialize(name, recorder)
      @name = name
      @recorder = recorder
    end

    def call(*_args)
      @recorder << [@name, 'before']
      yield
      @recorder << [@name, 'after']
    end
  end

  it 'executes middleware in the proper order' do
    msg = Sidekiq.dump_json({ 'class' => CustomWorker.to_s, 'args' => [$recorder] })

    Sidekiq.server_middleware do |chain|
      # should only add once, second should replace the first
      2.times { |i| chain.add CustomMiddleware, i.to_s, $recorder }
      chain.insert_before CustomMiddleware, AnotherCustomMiddleware, '2', $recorder
      chain.insert_after AnotherCustomMiddleware, YetAnotherCustomMiddleware, '3', $recorder
    end

    boss = Minitest::Mock.new
    opts = { queues: ['default'] }
    processor = Sidekiq::Processor.new(boss, opts)
    boss.expect(:processor_done, nil, [processor])
    processor.process(Sidekiq::BasicFetch::UnitOfWork.new('queue:default', msg))
    assert_equal %w[2 before 3 before 1 before work_performed 1 after 3 after 2 after], $recorder.flatten
  end

  it 'correctly replaces middleware when using middleware with options in the initializer' do
    chain = Sidekiq::Middleware::Chain.new
    chain.add NonYieldingMiddleware
    chain.add NonYieldingMiddleware, { foo: 5 }
    assert_equal 1, chain.count
  end

  it 'correctly prepends middleware' do
    chain = Sidekiq::Middleware::Chain.new
    chain_entries = chain.entries
    chain.add CustomMiddleware
    chain.prepend YetAnotherCustomMiddleware
    assert_equal YetAnotherCustomMiddleware, chain_entries.first.klass
    assert_equal CustomMiddleware, chain_entries.last.klass
  end

  it 'allows middleware to abruptly stop processing rest of chain' do
    recorder = []
    chain = Sidekiq::Middleware::Chain.new
    chain.add NonYieldingMiddleware
    chain.add CustomMiddleware, 1, recorder

    final_action = nil
    chain.invoke { final_action = true }
    assert_nil final_action
    assert_equal [], recorder
  end

  it 'allows middleware to yield arguments' do
    chain = Sidekiq::Middleware::Chain.new
    chain.add ArgumentYieldingMiddleware

    final_action = nil
    chain.invoke { final_action = true }
    assert_equal true, final_action
  end

  describe 'I18n' do
    before do
      require 'i18n'
      I18n.enforce_available_locales = false
      require 'sidekiq/middleware/i18n'
    end

    it 'saves and restores locale' do
      I18n.locale = 'fr'
      msg = {}
      mw = Sidekiq::Middleware::I18n::Client.new
      mw.call(nil, msg, nil, nil) {}
      assert_equal :fr, msg['locale']

      msg['locale'] = 'jp'
      I18n.locale = I18n.default_locale
      assert_equal :en, I18n.locale
      mw = Sidekiq::Middleware::I18n::Server.new
      mw.call(nil, msg, nil) do
        assert_equal :jp, I18n.locale
      end
      assert_equal :en, I18n.locale
    end

    it 'supports I18n.enforce_available_locales = true' do
      I18n.enforce_available_locales = true
      I18n.available_locales = %i[en jp]

      msg = { 'locale' => 'jp' }
      mw = Sidekiq::Middleware::I18n::Server.new
      mw.call(nil, msg, nil) do
        assert_equal :jp, I18n.locale
      end

      I18n.enforce_available_locales = false
      I18n.available_locales = nil
    end
  end
end
