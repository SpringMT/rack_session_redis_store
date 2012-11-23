#!/usr/bin/env ruby
# encoding: UTF-8

require File.dirname(__FILE__) + '/spec_helper'

require 'rack/mock'
require 'thread'
require 'json'

describe RackSessionRedisStore::Session do
  session_key = RackSessionRedisStore::Session::DEFAULT_OPTIONS[:key]
  session_match = /#{session_key}=([0-9a-fA-F]+);/
  incrementor = lambda do |env|
    env["rack.session"]["counter"] ||= 0
    env["rack.session"]["counter"] += 1
    Rack::Response.new(env["rack.session"].inspect).to_a
  end
  drop_session = proc do |env|
    env['rack.session.options'][:drop] = true
    incrementor.call(env)
  end
  renew_session = proc do |env|
    env['rack.session.options'][:renew] = true
    incrementor.call(env)
  end
  defer_session = proc do |env|
    env['rack.session.options'][:defer] = true
    incrementor.call(env)
  end

  it "creates a new cookie" do
    pool = RackSessionRedisStore::Session.new(incrementor)
    res = Rack::MockRequest.new(pool).get("/")
    res["Set-Cookie"].should be_include("#{session_key}=")
    res.body.should be_eql('{"counter"=>1}')
  end

  it "determines session from a cookie" do
    pool = RackSessionRedisStore::Session.new(incrementor)
    req = Rack::MockRequest.new(pool)
    res = req.get("/")
    cookie = res["Set-Cookie"]
    req.get("/", "HTTP_COOKIE" => cookie).
     body.should be_eql('{"counter"=>2}')
    req.get("/", "HTTP_COOKIE" => cookie).
      body.should be_eql('{"counter"=>3}')
  end

  it "determines session only from a cookie by default" do
    pool = RackSessionRedisStore::Session.new(incrementor)
    req = Rack::MockRequest.new(pool)
    res = req.get("/")
    sid = res["Set-Cookie"][session_match, 1]
    req.get("/?rack.session=#{sid}").
      body.should be_eql('{"counter"=>1}')
    req.get("/?rack.session=#{sid}").
      body.should be_eql('{"counter"=>1}')
  end

  it "determines session from params" do
    pool = RackSessionRedisStore::Session.new(incrementor, :cookie_only => false)
    req = Rack::MockRequest.new(pool)
    res = req.get("/")
    sid = res["Set-Cookie"][session_match, 1]
    req.get("/?rack.session=#{sid}").
      body.should be_eql('{"counter"=>2}')
    req.get("/?rack.session=#{sid}").
      body.should be_eql('{"counter"=>3}')
  end

  it "survives nonexistant cookies" do
    bad_cookie = "rack.session=blarghfasel"
    pool = RackSessionRedisStore::Session.new(incrementor)
    res = Rack::MockRequest.new(pool).
      get("/", "HTTP_COOKIE" => bad_cookie)
    res.body.should be_eql('{"counter"=>1}')
    cookie = res["Set-Cookie"][session_match]
    cookie.should_not match(/#{bad_cookie}/)
  end

  it "maintains freshness" do
    pool = RackSessionRedisStore::Session.new(incrementor, :expire_after => 3)
    res = Rack::MockRequest.new(pool).get('/')
    res.body.should be_include('"counter"=>1')
    cookie = res["Set-Cookie"]
    sid = cookie[session_match, 1]
    res = Rack::MockRequest.new(pool).get('/', "HTTP_COOKIE" => cookie)
    res["Set-Cookie"][session_match, 1].should be_eql(sid)
    res.body.should be_include('"counter"=>2')
    puts 'Sleeping to expire session' if $DEBUG
    sleep 4
    res = Rack::MockRequest.new(pool).get('/', "HTTP_COOKIE" => cookie)
    res["Set-Cookie"][session_match, 1].should_not be_eql(sid)
    res.body.should be_include('"counter"=>1')
  end

  it "does not send the same session id if it did not change" do
    pool = RackSessionRedisStore::Session.new(incrementor)
    req = Rack::MockRequest.new(pool)

    res0 = req.get("/")
    cookie = res0["Set-Cookie"]
    res0.body.should be_eql('{"counter"=>1}')

    res1 = req.get("/", "HTTP_COOKIE" => cookie)
    res1["Set-Cookie"].should be_nil
    res1.body.should be_eql('{"counter"=>2}')

    res2 = req.get("/", "HTTP_COOKIE" => cookie)
    res2["Set-Cookie"].should be_nil
    res2.body.should be_eql('{"counter"=>3}')
  end

  it "deletes cookies with :drop option" do
    pool = RackSessionRedisStore::Session.new(incrementor)
    req = Rack::MockRequest.new(pool)
    drop = Rack::Utils::Context.new(pool, drop_session)
    dreq = Rack::MockRequest.new(drop)

    res1 = req.get("/")
    session = (cookie = res1["Set-Cookie"])[session_match]
    res1.body.should be_eql('{"counter"=>1}')

    res2 = dreq.get("/", "HTTP_COOKIE" => cookie)
    res2["Set-Cookie"].should be_nil
    res2.body.should be_eql('{"counter"=>2}')

    res3 = req.get("/", "HTTP_COOKIE" => cookie)
    res3["Set-Cookie"][session_match].should_not be_eql(session)
    res3.body.should be_eql('{"counter"=>1}')
  end

  it "provides new session id with :renew option" do
    pool = RackSessionRedisStore::Session.new(incrementor)
    req = Rack::MockRequest.new(pool)
    renew = Rack::Utils::Context.new(pool, renew_session)
    rreq = Rack::MockRequest.new(renew)

    res1 = req.get("/")
    session = (cookie = res1["Set-Cookie"])[session_match]
    res1.body.should be_eql('{"counter"=>1}')

    res2 = rreq.get("/", "HTTP_COOKIE" => cookie)
    new_cookie = res2["Set-Cookie"]
    new_session = new_cookie[session_match]
    new_session.should_not be_eql(session)
    res2.body.should be_eql('{"counter"=>2}')

    res3 = req.get("/", "HTTP_COOKIE" => new_cookie)
    res3.body.should be_eql('{"counter"=>3}')

    # Old cookie was deleted
    res4 = req.get("/", "HTTP_COOKIE" => cookie)
    res4.body.should be_eql('{"counter"=>1}')
  end

  it "omits cookie with :defer option" do
    pool = RackSessionRedisStore::Session.new(incrementor)
    defer = Rack::Utils::Context.new(pool, defer_session)
    dreq = Rack::MockRequest.new(defer)

    res0 = dreq.get("/")
    res0["Set-Cookie"].should be_nil
    res0.body.should be_eql('{"counter"=>1}')
  end

  it "updates deep hashes correctly" do
    hash_check = proc do |env|
      session = env['rack.session']
      unless session.include? 'test'
        session.update :a => :b, :c => { :d => :e },
          :f => { :g => { :h => :i} }, 'test' => true
      else
        session[:f][:g][:h] = :j
      end
      [200, {}, [session.inspect]]
    end
    pool = RackSessionRedisStore::Session.new(hash_check)
    req = Rack::MockRequest.new(pool)

    res0 = req.get("/")
    session_id = (cookie = res0["Set-Cookie"])[session_match, 1]
    ses0 = pool.pool.get(session_id)

    req.get("/", "HTTP_COOKIE" => cookie)
    ses1 = pool.pool.get(session_id)

    ses1.should_not be_eql(ses0)
  end

  # anyone know how to do this better?
  it "cleanly merges sessions when multithreaded" do
    unless $DEBUG
      1.should be_eql(1) # fake assertion to appease the mighty bacon
      next
    end
    warn 'Running multithread test for RackSessionRedisStore::Session'
    pool = RackSessionRedisStore::Session.new(incrementor)
    req = Rack::MockRequest.new(pool)

    res = req.get('/')
    res.body.should be_eql('{"counter"=>1}')
    cookie = res["Set-Cookie"]
    session_id = cookie[session_match, 1]

    delta_incrementor = lambda do |env|
      # emulate disconjoinment of threading
      env['rack.session'] = env['rack.session'].dup
      Thread.stop
      env['rack.session'][(Time.now.usec*rand).to_i] = true
      incrementor.call(env)
    end
    tses = Rack::Utils::Context.new pool, delta_incrementor
    treq = Rack::MockRequest.new(tses)
    tnum = rand(7).to_i+5
    r = Array.new(tnum) do
      Thread.new(treq) do |run|
        run.get('/', "HTTP_COOKIE" => cookie, 'rack.multithread' => true)
      end
    end.reverse.map{|t| t.run.join.value }
    r.each do |request|
      request['Set-Cookie'].should be_eql(cookie)
      request.body.should be_include('"counter"=>2')
    end

    session = pool.pool.get(session_id)
    session.size.should be_eql(tnum+1) # counter
    session['counter'].should be_eql(2) # meeeh

    tnum = rand(7).to_i+5
    r = Array.new(tnum) do |i|
      app = Rack::Utils::Context.new pool, time_delta
      req = Rack::MockRequest.new app
      Thread.new(req) do |run|
        run.get('/', "HTTP_COOKIE" => cookie, 'rack.multithread' => true)
      end
    end.reverse.map{|t| t.run.join.value }
    r.each do |request|
      request['Set-Cookie'].should be_eql(cookie)
      request.body.should be_include('"counter"=>3')
    end

    session = pool.pool.get(session_id)
    session.size.should be_eql(tnum+1)
    session['counter'].should be_eql(3)

    drop_counter = proc do |env|
      env['rack.session'].delete 'counter'
      env['rack.session']['foo'] = 'bar'
      [200, {'Content-Type'=>'text/plain'}, env['rack.session'].inspect]
    end
    tses = Rack::Utils::Context.new pool, drop_counter
    treq = Rack::MockRequest.new(tses)
    tnum = rand(7).to_i+5
    r = Array.new(tnum) do
      Thread.new(treq) do |run|
        run.get('/', "HTTP_COOKIE" => cookie, 'rack.multithread' => true)
      end
    end.reverse.map{|t| t.run.join.value }
    r.each do |request|
      request['Set-Cookie'].should be_eql(cookie)
      request.body.should be_include('"foo"=>"bar"')
    end

    session = pool.pool.get(session_id)
    session.size.should be_eql(r.size+1)
    session['counter'].should be_nil
    session['foo'].should be_eql('bar')
  end

  it "handles a flash object" do
    flash_set = proc do |env|
      session = env['rack.session']
      session[:flash] = {notice: 'notice foo', alert: 'alert bar'}
      # get_session() is called when session is refferd first
      [200, {}, [session[:flash]]] ## set_session() is called at last
    end
    flash_get = proc do |env|
      session = env['rack.session']
      [200, {}, [session['flash']]]
    end
    pool_set = RackSessionRedisStore::Session.new flash_set
    req0 = Rack::MockRequest.new pool_set
    res = req0.get "/"
    cookie = res["Set-Cookie"]
    cookie.should be_include "#{session_key}="
    pool_get = RackSessionRedisStore::Session.new flash_get
    req1 = Rack::MockRequest.new pool_get
    body1 = req1.get("/", "HTTP_COOKIE" => cookie).body
    # Rack::MockRequest returns a to_s body. See lib/rack/mock.rb
    body1.should eql({notice: 'notice foo', alert: 'alert bar'}.to_s)
  end

end

