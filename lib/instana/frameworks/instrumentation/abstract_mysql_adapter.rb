module Instana
  module Instrumentation
    module AbstractMysqlAdapter
      IGNORED_PAYLOADS = %w(SCHEMA EXPLAIN CACHE).freeze
      EXPLAINED_SQLS = /\A\s*(with|select|update|delete|insert)\b/i

      # This module supports instrumenting ActiveRecord with the mysql2 adapter.
      #
      def self.included(klass)
        if ActiveRecord::VERSION::STRING >= '3.2'
          Instana::Util.method_alias(klass, :execute)

          @@sanitize_regexp = Regexp.new('(\'[\s\S][^\']*\'|\d*\.\d+|\d+|NULL)', Regexp::IGNORECASE)
        end
      end

      # Collect up this DB connection info for reporting.
      #
      # @param sql [String]
      # @return [Hash] Hash of collected KVs
      #
      def collect(sql)
        payload = { :activerecord => {} }
        payload[:activerecord][:sql] = sql.gsub(@@sanitize_regexp, '?')
        payload[:activerecord][:adapter] = @config[:adapter]
        payload[:activerecord][:host] = @config[:host]
        payload[:activerecord][:db] = @config[:database]
        payload[:activerecord][:username] = @config[:username]
        payload
      end

      # In the spirit of ::ActiveRecord::ExplainSubscriber.ignore_payload?  There are
      # only certain calls that we're interested in tracing.  e.g. No use to instrument
      # framework caches.
      #
      # @param payload [String]
      # @return [Boolean]
      #
      def ignore_payload?(name, sql)
        IGNORED_PAYLOADS.include?(name) || sql !~ EXPLAINED_SQLS
      end

      def execute_with_instana(sql, name = nil)
        tracing = ::Instana.tracer.tracing?
        if !tracing || ignore_payload?(name, sql)
          return execute_without_instana(sql, name)
        elsif ::Instana.tracer.current_span[:n] == :activerecord
          return execute_without_instana(sql, name)
        end

        kv_payload = collect(sql)
        ::Instana.tracer.trace(:activerecord, kv_payload) do
          execute_without_instana(sql, name)
        end
      end
    end
  end
end
