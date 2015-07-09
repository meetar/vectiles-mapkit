require 'webrick'
WEBrick::HTTPServer.new(:DocumentRoot => "./", :Port => 8080).start
