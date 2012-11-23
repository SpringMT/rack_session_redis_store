# encoding: UTF-8

require 'thread'
require 'base64'
require 'rack/session/abstract/id'
require 'redis_json_serializer'

#
# == Synopsis
#
# session store in redis
#
# == Description
#
# === Example
#
# === Features
#
# == HOWTOs
#


module RackSessionRedisStore
  class Session < ::Rack::Session::Abstract::ID
    attr_reader :mutex, :pool
    DEFAULT_OPTIONS = ::Rack::Session::Abstract::ID::DEFAULT_OPTIONS

    def initialize(app, options = {})
      super
      @mutex = Mutex.new
      host = options[:host] || '127.0.0.1'
      port = options[:port] || 6379
      namespace = options[:namespace] || :session
      @pool  = RedisJsonSerializer::Serializer.new(host: host, port: port, namespace: namespace)
    end

    def generate_sid
      loop do
        sid = super
        break sid unless @pool.get sid
      end
    end

    # === Synopsis
    # call at call -> context -> prepare_session -> SessionHash.new  in rack/session/abstract/id.rb
    #
    def get_session(env, sid)
      with_lock(env, [nil, {}]) do
        unless sid and session = @pool.get(sid)
          sid, session = generate_sid, {}
          unless /^OK/ =~ @pool.set(sid, session)
            raise "Session collision on '#{sid.inspect}'"
          end
        end
        if session.has_key? :flash
          session[:flash] = Marshal.load(::Base64.decode64(session[:flash]))
        end
        [sid, session]
      end
    end

    # === Synopsis
    # call at call -> context -> commit_session in rack/session/abstract/id.rb
    #
    def set_session(env, session_id, new_session, options)
      with_lock(env, false) do
        if new_session.has_key? 'flash'
          new_session['flash'] = ::Base64.encode64(Marshal.dump(new_session['flash']))
        end
        if ttl = options[:expire_after]
          @pool.setex session_id, ttl, new_session
        else
          @pool.set session_id, new_session
        end
        session_id
      end
    end

    def destroy_session(env, session_id, options)
      with_lock(env) do
        @pool.del session_id
        generate_sid unless options[:drop]
      end
    end

    def with_lock(env, default=nil)
      @mutex.lock if env['rack.multithread']
      yield
    rescue Errno::ECONNREFUSED
      if $VERBOSE
        warn "#{self} is unable to find Redis server."
        warn $!.inspect
      end
      default
    ensure
      @mutex.unlock if @mutex.locked?
    end

  end
end
