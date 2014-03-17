require "rm-extensions-firebase/version"

unless defined?(Motion::Project::Config)
  raise "This file must be required within a RubyMotion project Rakefile."
end

Motion::Project::App.setup do |app|
  %w(
    firebase_ext
  ).reverse.each do |x|
    app.files.unshift(File.join(File.dirname(__FILE__), "motion/#{x}.rb"))
  end
end
