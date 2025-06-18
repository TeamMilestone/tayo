# frozen_string_literal: true

require "fileutils"
require "colorize"

module Tayo
  class DockerfileModifier
    attr_reader :project_path, :dockerfile_path

    def initialize(project_path = Dir.pwd)
      @project_path = project_path
      @dockerfile_path = File.join(project_path, 'Dockerfile')
    end

    def init
      unless File.exist?(dockerfile_path)
        raise "Dockerfile not found in #{project_path}"
      end

      backup_dockerfile
      modify_dockerfile
    end

    private

    def backup_dockerfile
      backup_path = File.join(project_path, 'Dockerfile.origin')
      FileUtils.cp(dockerfile_path, backup_path)
      puts "✅ Dockerfile 백업이 생성되었습니다: #{backup_path}".colorize(:green) if defined?(String.colorize)
    end

    # =================================================================
    # === 수정된 핵심 로직 ===
    # =================================================================
    def modify_dockerfile
      content = File.read(dockerfile_path)

      # 1. `bundle install` 라인의 마지막에 붙어있는 bootsnap 부분을 제거합니다.
      #    - `&& \` 와 함께 `bootsnap precompile --gemfile` 부분을 찾아서 빈 문자열로 만듭니다.
      modified_content = content.gsub(/\s*&& \\\s*bundle exec bootsnap precompile --gemfile/, '')

      # 2. 단독으로 존재하는 `bootsnap precompile app/ lib/` 라인을 주석 처리합니다.
      #    - 라인 시작(`^`)부터 확인하여 정확히 해당 라인만 대상으로 삼습니다.
      #    - 원래의 들여쓰기를 보존하기 위해 앞부분의 공백(`\s*`)을 캡처(`()`)했다가 다시 사용(`\1`)합니다.
      modified_content.gsub!(/^(\s*)RUN bundle exec bootsnap precompile app\/ lib\//, '\1# RUN bundle exec bootsnap precompile app/ lib/')

      File.write(dockerfile_path, modified_content)
      puts "✅ Dockerfile에서 bootsnap 부분이 비활성화되었습니다.".colorize(:green) if defined?(String.colorize)
    end
  end
end