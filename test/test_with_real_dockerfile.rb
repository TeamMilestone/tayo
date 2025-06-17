#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/tayo"
require "fileutils"
require "colorize"

# test 디렉토리로 이동
test_dir = File.dirname(__FILE__)
Dir.chdir(test_dir)

puts "테스트 디렉토리: #{Dir.pwd}"
puts "Dockerfile 존재: #{File.exist?('Dockerfile')}"

# Dockerfile 백업
FileUtils.cp("Dockerfile", "Dockerfile.backup")

# Init 인스턴스 생성
init = Tayo::Commands::Init.new

# 원본 내용 확인
original_content = File.read("Dockerfile")
puts "\n원본 Dockerfile에서 bootsnap 검색:"
original_content.lines.each_with_index do |line, index|
  if line.include?("bootsnap")
    puts "  라인 #{index + 1}: #{line.strip}"
  end
end

# fix_dockerfile_bootsnap_issue 실행
puts "\n메서드 실행 중..."
init.send(:fix_dockerfile_bootsnap_issue)

# 수정된 내용 확인
modified_content = File.read("Dockerfile")
puts "\n수정된 Dockerfile에서 bootsnap 검색:"
modified_content.lines.each_with_index do |line, index|
  if line.include?("bootsnap")
    puts "  라인 #{index + 1}: #{line.strip}"
  end
end

# 제거되어야 할 라인 확인
target_comment = "# Precompile bootsnap code for faster boot times"
target_command = "RUN bundle exec bootsnap precompile app/ lib/"

puts "\n확인 결과:"
puts "주석 라인 제거됨? #{!modified_content.include?(target_comment)}"
puts "RUN 명령 제거됨? #{!modified_content.include?(target_command)}"

# 원본 복원
FileUtils.mv("Dockerfile.backup", "Dockerfile", force: true)

# 패턴 매칭 디버깅
puts "\n패턴 매칭 디버깅:"
comment_pattern = /^\s*# Precompile bootsnap code for faster boot times/i
run_command_pattern = /^\s*RUN bundle exec bootsnap precompile app\/ lib\//i

original_content.lines.each_with_index do |line, index|
  if line.match?(comment_pattern)
    puts "주석 패턴 매치: 라인 #{index + 1}"
  end
  if line.match?(run_command_pattern)
    puts "RUN 패턴 매치: 라인 #{index + 1}"
  end
end