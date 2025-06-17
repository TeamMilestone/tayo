# Tayo 실행 환경 문제 해결 가이드

## 1. 현재 설치된 gem 버전 확인

```bash
# 시스템에 설치된 tayo gem 버전 확인
gem list tayo

# 프로젝트에서 사용 중인 버전 확인 (Bundler 사용 시)
bundle show tayo

# 어느 위치의 gem이 실행되는지 확인
which tayo
gem which tayo
```

## 2. 버전 업데이트

### 시스템 전체 gem 업데이트
```bash
# 최신 버전으로 업데이트
gem update tayo

# 특정 버전 설치
gem install tayo -v 0.1.7

# 기존 버전 모두 제거 후 재설치
gem uninstall tayo --all
gem install tayo
```

### Bundler 사용 시
```bash
# Gemfile에서 버전 확인
cat Gemfile | grep tayo

# bundle update
bundle update tayo

# 또는 Gemfile에 버전 명시
# gem 'tayo', '~> 0.1.7'

# bundle install
bundle install
```

## 3. 실행 방법별 확인

### 직접 실행
```bash
tayo init
```

### Bundle exec 사용
```bash
bundle exec tayo init
```

### 프로젝트 내 개발 버전 사용
```bash
# Gemfile에 로컬 경로 지정
# gem 'tayo', path: '/path/to/tayo'
```

## 4. 디버깅 정보 수집

다음 스크립트를 실행하여 환경 정보를 수집하세요:

```ruby
# debug_tayo.rb
puts "=== Tayo 디버깅 정보 ==="
puts "Ruby 버전: #{RUBY_VERSION}"
puts "Bundler 사용: #{defined?(Bundler) ? 'Yes' : 'No'}"

require 'tayo/version'
puts "Tayo 버전: #{Tayo::VERSION}"

require 'tayo/commands/init'
init = Tayo::Commands::Init.new

# gem 위치 확인
spec = Gem::Specification.find_by_name('tayo')
puts "Gem 위치: #{spec.gem_dir}"
puts "Gem 버전: #{spec.version}"

# 메서드 존재 확인
puts "fix_dockerfile_bootsnap_issue 메서드 존재: #{init.respond_to?(:fix_dockerfile_bootsnap_issue, true)}"

# 메서드 위치 확인
if init.respond_to?(:fix_dockerfile_bootsnap_issue, true)
  method = init.method(:fix_dockerfile_bootsnap_issue)
  puts "메서드 정의 위치: #{method.source_location}"
end
```

## 5. 캐시 문제 해결

### RubyGems 캐시 정리
```bash
gem cleanup tayo
```

### Bundler 캐시 정리
```bash
bundle clean --force
rm -rf .bundle
bundle install
```

## 6. 수동 테스트

프로젝트 디렉토리에서 직접 테스트:

```ruby
# irb 또는 rails console에서
require 'tayo'
init = Tayo::Commands::Init.new
init.send(:fix_dockerfile_bootsnap_issue)
```

## 7. 일반적인 문제와 해결법

### 문제: "undefined method" 에러
- 원인: 오래된 버전 사용
- 해결: `gem update tayo`

### 문제: Bundler가 다른 버전 사용
- 원인: Gemfile.lock에 고정된 버전
- 해결: `bundle update tayo`

### 문제: 여러 버전 설치로 인한 충돌
- 원인: 시스템과 프로젝트 버전 충돌
- 해결: 
  ```bash
  gem uninstall tayo --all
  bundle install
  ```

### 문제: 권한 문제
- 원인: 시스템 gem 디렉토리 권한
- 해결: 
  ```bash
  # rbenv/rvm 사용 권장
  # 또는
  gem install tayo --user-install
  ```

## 8. 버전별 기능 확인

- v0.1.4: bootsnap 제거 기능 첫 추가
- v0.1.5: 라인별 처리 방식
- v0.1.6: reject 방식으로 개선
- v0.1.7: 테스트 추가 및 개행 문자 처리 수정

필요한 최소 버전: **0.1.6 이상**