# RackSessionRedisStore [![Build Status](https://travis-ci.org/SpringMT/rack_session_redis_store.png)](https://travis-ci.org/SpringMT/rack_session_redis_store)

RackSessionRedisStore is to manage session using redis.

## Usage
For Rails.

In config/initializers/session_store.rb

~~~
# Be sure to restart your server when you modify this file.
require 'session/redis'
Cowork::Application.config.session_store RackSessionRedisStore::Session, key: '_session', host: '127.0.0.1'

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rails generate session_migration")
# Cowork::Application.config.session_store :active_record_store
~~~


## Installation

Add this line to your application's Gemfile:

    gem 'rack_session_redis_store'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rack_session_redis_store

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
