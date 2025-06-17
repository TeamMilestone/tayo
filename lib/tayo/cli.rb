# frozen_string_literal: true

require "thor"
require "colorize"
require_relative "commands/init"
require_relative "commands/gh"
require_relative "commands/cf"

module Tayo
  class CLI < Thor
    desc "init", "Rails 프로젝트에 Tayo를 설정합니다"
    def init
      Commands::Init.new.execute
    end

    desc "gh", "GitHub 저장소와 컨테이너 레지스트리를 설정합니다"
    def gh
      Commands::Gh.new.execute
    end

    desc "cf", "Cloudflare DNS를 설정하여 홈서버에 도메인을 연결합니다"
    def cf
      Commands::Cf.new.execute
    end

    desc "version", "Tayo 버전을 표시합니다"
    def version
      puts "Tayo #{VERSION}"
    end
  end
end