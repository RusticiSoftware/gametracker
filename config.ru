require 'gametracker'

set :root, File.dirname(__FILE__)
set :environment, :development
log = File.new("sinatra.log", "a+")
$stdout.reopen(log)
$stderr.reopen(log)

run GameTracker
