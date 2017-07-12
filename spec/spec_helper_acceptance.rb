require 'beaker-rspec/spec_helper'
require 'beaker-rspec/helpers/serverspec'


RSpec.configure do |c|
  # Readable test descriptions
  c.formatter = :documentation
  hosts.each do |host|
    sleep(180)
  end
end
