# frozen_string_literal: true

require_relative "lib/tayo/version"

Gem::Specification.new do |spec|
  spec.name = "tayo"
  spec.version = Tayo::VERSION
  spec.authors = ["이원섭wonsup Lee/Alfonso"]
  spec.email = ["onesup.lee@gmail.com"]

  spec.summary = "Rails deployment tool for home servers"
  spec.description = "Tayo is a deployment tool for Rails applications to home servers using GitHub Container Registry and Cloudflare CLI."
  spec.homepage = "https://github.com/TeamMilestone/tayo"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/TeamMilestone/tayo"
  spec.metadata["changelog_uri"] = "https://github.com/TeamMilestone/tayo/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "git", "~> 1.18"
  spec.add_dependency "colorize", "~> 1.1"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "logger", "~> 1.6"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
