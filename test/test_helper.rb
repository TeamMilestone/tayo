# frozen_string_literal: true

require "minitest/autorun"
require "colorize"
require "tempfile"
require "fileutils"

# Load the tayo library
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "tayo"