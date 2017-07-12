require 'fileutils'
require 'rake'
require 'rspec/core/rake_task'
require 'tmpdir'
require 'yaml'

# creates a logger so we can log events with certain levels
def logger
  unless @logger
    require 'logger'
    if ENV['ENABLE_LOGGER']
       level = Logger::DEBUG
     else
       level = Logger::INFO
    end
    @logger = Logger.new(STDOUT)
    @logger.level = level
  end
  @logger
end

desc "Run beaker acceptance tests"
RSpec::Core::RakeTask.new(:beaker) do |t|
  t.rspec_opts = ['--color']
  t.pattern = 'spec/acceptance'
end

# get the array of Beaker set names
# @return [Array<String>]
def beaker_node_sets
  return @beaker_nodes if @beaker_nodes
  @beaker_nodes = Dir['spec/acceptance/nodesets/*.yml'].sort.map do |node_set|
    node_set.slice!('.yml')
    File.basename(node_set)
  end
end

beaker_node_sets.each do |set|
  desc "Run the Beaker acceptance tests for the node set '#{set}'"
  task "beaker:#{set}" do
    ENV['BEAKER_set'] = set
    Rake::Task['beaker'].reenable
    Rake::Task['beaker'].invoke
  end
end
