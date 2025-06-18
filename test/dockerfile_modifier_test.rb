# frozen_string_literal: true

require "test_helper"
require "tayo/dockerfile_modifier"
require "fileutils"
require "tmpdir"

class DockerfileModifierTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @dockerfile_path = File.join(@temp_dir, 'Dockerfile')
    @modifier = Tayo::DockerfileModifier.new(@temp_dir)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_raises_error_when_dockerfile_not_found
    assert_raises(RuntimeError) do
      @modifier.init
    end
  end

  def test_creates_backup_file
    # 원본 Dockerfile 생성
    File.write(@dockerfile_path, "FROM ruby:3.4.4\nRUN echo 'test'")
    
    @modifier.init
    
    backup_path = File.join(@temp_dir, 'Dockerfile.origin')
    assert File.exist?(backup_path)
    assert_equal File.read(@dockerfile_path), File.read(backup_path)
  end

  def test_removes_bootsnap_precompile_with_gemfile_option
    dockerfile_content = <<~DOCKERFILE
      FROM ruby:3.4.4
      RUN bundle install && \\
          rm -rf ~/.bundle/ && \\
          bundle exec bootsnap precompile --gemfile
    DOCKERFILE

    File.write(@dockerfile_path, dockerfile_content)
    @modifier.init

    modified_content = File.read(@dockerfile_path)
    refute_includes modified_content, "bundle exec bootsnap precompile --gemfile"
    assert_includes modified_content, "bundle install"
  end

  def test_comments_out_standalone_bootsnap_precompile_line
    dockerfile_content = <<~DOCKERFILE
      FROM ruby:3.4.4
      COPY . .
      # Precompile bootsnap code for faster boot times
      RUN bundle exec bootsnap precompile app/ lib/
      RUN echo 'other command'
    DOCKERFILE

    File.write(@dockerfile_path, dockerfile_content)
    @modifier.init

    modified_content = File.read(@dockerfile_path)
    assert_includes modified_content, "# RUN bundle exec bootsnap precompile app/ lib/"
    refute_match /^RUN bundle exec bootsnap precompile app\/ lib\/$/, modified_content
  end

  def test_preserves_indentation_when_commenting_out
    dockerfile_content = <<~DOCKERFILE
      FROM ruby:3.4.4
      COPY . .
          RUN bundle exec bootsnap precompile app/ lib/
      RUN echo 'other command'
    DOCKERFILE

    File.write(@dockerfile_path, dockerfile_content)
    @modifier.init

    modified_content = File.read(@dockerfile_path)
    assert_includes modified_content, "    # RUN bundle exec bootsnap precompile app/ lib/"
  end

  def test_handles_both_bootsnap_patterns_in_same_file
    dockerfile_content = <<~DOCKERFILE
      FROM ruby:3.4.4
      COPY Gemfile Gemfile.lock ./
      RUN bundle install && \\
          rm -rf ~/.bundle/ && \\
          bundle exec bootsnap precompile --gemfile
      
      COPY . .
      # Precompile bootsnap code for faster boot times
      RUN bundle exec bootsnap precompile app/ lib/
    DOCKERFILE

    File.write(@dockerfile_path, dockerfile_content)
    @modifier.init

    modified_content = File.read(@dockerfile_path)
    
    # --gemfile 옵션이 있는 bootsnap은 제거되어야 함
    refute_includes modified_content, "bundle exec bootsnap precompile --gemfile"
    
    # app/ lib/ 타겟 bootsnap은 주석 처리되어야 함
    assert_includes modified_content, "# RUN bundle exec bootsnap precompile app/ lib/"
    refute_match /^RUN bundle exec bootsnap precompile app\/ lib\/$/, modified_content
  end

  def test_does_not_modify_other_bootsnap_commands
    dockerfile_content = <<~DOCKERFILE
      FROM ruby:3.4.4
      RUN bundle exec bootsnap setup
      RUN bundle exec bootsnap --help
      RUN bundle exec bootsnap precompile app/ lib/
    DOCKERFILE

    File.write(@dockerfile_path, dockerfile_content)
    @modifier.init

    modified_content = File.read(@dockerfile_path)
    
    # 다른 bootsnap 명령어들은 그대로 유지되어야 함
    assert_includes modified_content, "bundle exec bootsnap setup"
    assert_includes modified_content, "bundle exec bootsnap --help"
    
    # 특정 패턴만 주석 처리되어야 함
    assert_includes modified_content, "# RUN bundle exec bootsnap precompile app/ lib/"
  end

  def test_works_with_real_dockerfile
    # 테스트 폴더의 실제 Dockerfile을 사용한 테스트
    real_dockerfile_path = File.join(File.dirname(__FILE__), 'Dockerfile')
    if File.exist?(real_dockerfile_path)
      real_content = File.read(real_dockerfile_path)
      File.write(@dockerfile_path, real_content)
      
      @modifier.init
      
      modified_content = File.read(@dockerfile_path)
      
      # 백업 파일이 생성되었는지 확인
      backup_path = File.join(@temp_dir, 'Dockerfile.origin')
      assert File.exist?(backup_path)
      
      # 원본 내용과 백업 내용이 같은지 확인
      assert_equal real_content, File.read(backup_path)
      
      # bootsnap 관련 수정이 적용되었는지 확인
      if real_content.include?("bundle exec bootsnap precompile --gemfile")
        refute_includes modified_content, "bundle exec bootsnap precompile --gemfile"
      end
      
      if real_content.match?(/^RUN bundle exec bootsnap precompile app\/ lib\//)
        assert_includes modified_content, "# RUN bundle exec bootsnap precompile app/ lib/"
      end
    end
  end
end