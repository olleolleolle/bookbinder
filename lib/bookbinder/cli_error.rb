module Bookbinder
  module CliError
    InvalidArguments = Class.new(StandardError)
    UnknownCommand = Class.new(StandardError)
  end
end
