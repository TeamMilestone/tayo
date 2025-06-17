# frozen_string_literal: true

require_relative "test_helper"

class DockerfileBootsnapTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @original_dir = Dir.pwd
    Dir.chdir(@temp_dir)
    
    # Init 인스턴스 생성
    @init = Tayo::Commands::Init.new
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@temp_dir)
  end

  def test_removes_bootsnap_lines_from_dockerfile
    # 테스트용 Dockerfile 생성
    dockerfile_content = <<~DOCKERFILE
      # syntax=docker/dockerfile:1
      # check=error=true

      # This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
      # docker build -t testsomething .
      # docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name testsomething testsomething

      # For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

      # Make sure RUBY_VERSION matches the Ruby version in .ruby-version
      ARG RUBY_VERSION=3.4.4
      FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

      # Rails app lives here
      WORKDIR /rails

      # Install base packages
      RUN apt-get update -qq && \\
          apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 && \\
          rm -rf /var/lib/apt/lists /var/cache/apt/archives

      # Set production environment
      ENV RAILS_ENV="production" \\
          BUNDLE_DEPLOYMENT="1" \\
          BUNDLE_PATH="/usr/local/bundle" \\
          BUNDLE_WITHOUT="development"

      # Throw-away build stage to reduce size of final image
      FROM base AS build

      # Install packages needed to build gems
      RUN apt-get update -qq && \\
          apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \\
          rm -rf /var/lib/apt/lists /var/cache/apt/archives

      # Install application gems
      COPY Gemfile Gemfile.lock ./
      RUN bundle install && \\
          rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \\
          bundle exec bootsnap precompile --gemfile

      # Copy application code
      COPY . .

      # Precompile bootsnap code for faster boot times
      RUN bundle exec bootsnap precompile app/ lib/

      # Precompiling assets for production without requiring secret RAILS_MASTER_KEY
      RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




      # Final stage for app image
      FROM base

      # Copy built artifacts: gems, application
      COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
      COPY --from=build /rails /rails

      # Run and own only the runtime files as a non-root user for security
      RUN groupadd --system --gid 1000 rails && \\
          useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \\
          chown -R rails:rails db log storage tmp
      USER 1000:1000

      # Entrypoint prepares the database.
      ENTRYPOINT ["/rails/bin/docker-entrypoint"]

      # Start server via Thruster by default, this can be overwritten at runtime
      EXPOSE 80
      CMD ["./bin/thrust", "./bin/rails", "server"]
    DOCKERFILE

    File.write("Dockerfile", dockerfile_content)
    
    # fix_dockerfile_bootsnap_issue 메서드 실행
    @init.send(:fix_dockerfile_bootsnap_issue)
    
    # 수정된 내용 읽기
    modified_content = File.read("Dockerfile")
    
    # bootsnap 관련 라인들이 제거되었는지 확인
    refute modified_content.include?("# Precompile bootsnap code for faster boot times"),
           "주석이 제거되지 않았습니다"
    refute modified_content.include?("RUN bundle exec bootsnap precompile app/ lib/"),
           "RUN 명령이 제거되지 않았습니다"
    
    # 다른 bootsnap 라인은 유지되어야 함
    assert modified_content.include?("bundle exec bootsnap precompile --gemfile"),
           "--gemfile 옵션이 있는 bootsnap 명령은 유지되어야 합니다"
    
    # 전체 구조가 유지되는지 확인
    assert modified_content.include?("# syntax=docker/dockerfile:1")
    assert modified_content.include?("FROM docker.io/library/ruby:")
    assert modified_content.include?("WORKDIR /rails")
    assert modified_content.include?("# Copy application code")
    assert modified_content.include?("COPY . .")
    assert modified_content.include?("# Precompiling assets for production")
  end

  def test_handles_missing_dockerfile
    # Dockerfile이 없는 경우
    refute File.exist?("Dockerfile")
    
    # 에러 없이 실행되어야 함
    assert_silent do
      @init.send(:fix_dockerfile_bootsnap_issue)
    end
  end

  def test_preserves_dockerfile_without_bootsnap
    # bootsnap이 없는 Dockerfile
    dockerfile_content = <<~DOCKERFILE
      FROM ruby:3.4.4
      WORKDIR /app
      COPY . .
      RUN bundle install
      CMD ["rails", "server"]
    DOCKERFILE

    File.write("Dockerfile", dockerfile_content)
    original_content = dockerfile_content.dup
    
    @init.send(:fix_dockerfile_bootsnap_issue)
    
    modified_content = File.read("Dockerfile")
    
    # 내용이 변경되지 않아야 함
    assert_equal original_content, modified_content,
                 "bootsnap이 없는 Dockerfile은 변경되지 않아야 합니다"
  end

  def test_handles_variations_in_spacing
    # 다양한 공백이 포함된 Dockerfile
    dockerfile_content = <<~DOCKERFILE
      FROM ruby:3.4.4
      
        # Precompile bootsnap code for faster boot times
        RUN bundle exec bootsnap precompile app/ lib/
      
      # 다른 내용
      RUN echo "test"
    DOCKERFILE

    File.write("Dockerfile", dockerfile_content)
    
    @init.send(:fix_dockerfile_bootsnap_issue)
    
    modified_content = File.read("Dockerfile")
    
    # 공백이 있어도 제거되어야 함
    refute modified_content.include?("Precompile bootsnap code for faster boot times")
    refute modified_content.include?("RUN bundle exec bootsnap precompile app/ lib/")
    
    # 다른 내용은 유지되어야 함
    assert modified_content.include?("# 다른 내용")
    assert modified_content.include?('RUN echo "test"')
  end

  def test_case_insensitive_matching
    # 대소문자가 다른 경우
    dockerfile_content = <<~DOCKERFILE
      FROM ruby:3.4.4
      
      # PRECOMPILE BOOTSNAP CODE FOR FASTER BOOT TIMES
      RUN bundle exec bootsnap precompile app/ lib/
      
      # Precompile Bootsnap Code For Faster Boot Times
      RUN bundle exec bootsnap precompile app/ lib/
    DOCKERFILE

    File.write("Dockerfile", dockerfile_content)
    
    @init.send(:fix_dockerfile_bootsnap_issue)
    
    modified_content = File.read("Dockerfile")
    
    # 대소문자와 관계없이 모두 제거되어야 함
    refute modified_content.match?(/precompile.*bootsnap.*faster boot times/i)
    refute modified_content.include?("RUN bundle exec bootsnap precompile app/ lib/")
  end
end