require "rm-extensions-firebase/version"

unless defined?(Motion::Project::Config)
  raise "This file must be required within a RubyMotion project Rakefile."
end

Motion::Project::App.setup do |app|
  index = app.files.rindex { |x| x.index("rm-extensions") }
  %w(
    firebase_ext
  ).reverse.each_with_index do |x, i|
    app.files.insert(index + 1 + i, File.join(File.dirname(__FILE__), "motion/#{x}.rb"))
  end
end
