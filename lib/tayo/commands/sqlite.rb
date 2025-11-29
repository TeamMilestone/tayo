# frozen_string_literal: true

require "colorize"
require "yaml"

module Tayo
  module Commands
    class Sqlite
      def execute
        puts "🗄️  SQLite 최적화 설정을 시작합니다...".colorize(:green)

        unless rails_project?
          puts "❌ Rails 프로젝트가 아닙니다. Rails 프로젝트 루트에서 실행해주세요.".colorize(:red)
          return
        end

        unless sqlite_project?
          puts "❌ SQLite를 사용하는 프로젝트가 아닙니다.".colorize(:red)
          return
        end

        unless rails_8_or_higher?
          puts "❌ Rails 8 이상이 필요합니다. (현재: Rails #{detect_rails_version || '알 수 없음'})".colorize(:red)
          puts "   Solid Cable은 Rails 8에서 도입되었습니다.".colorize(:yellow)
          return
        end

        puts "   Rails #{detect_rails_version} 확인됨".colorize(:gray)

        add_solid_cable_gem
        run_bundle_install
        install_solid_cable
        update_database_yml
        update_cable_yml
        create_sqlite_initializer
        run_migrations
        create_documentation

        puts ""
        puts "✅ SQLite + Solid Cable 최적화 설정이 완료되었습니다!".colorize(:green)
        puts "   📄 설정 배경 문서: docs/solid-cable-sqlite-setup.md".colorize(:gray)
      end

      private

      def rails_project?
        File.exist?("Gemfile") && File.exist?("config/application.rb")
      end

      def sqlite_project?
        return false unless File.exist?("config/database.yml")

        database_yml = File.read("config/database.yml")
        database_yml.include?("sqlite3")
      end

      def rails_8_or_higher?
        version = detect_rails_version
        return false unless version

        major_version = version.split(".").first.to_i
        major_version >= 8
      end

      def detect_rails_version
        # Gemfile.lock에서 rails 버전 확인
        if File.exist?("Gemfile.lock")
          lockfile = File.read("Gemfile.lock")
          if match = lockfile.match(/^\s+rails\s+\((\d+\.\d+\.\d+)/)
            return match[1]
          end
        end

        # Gemfile에서 확인 (edge rails 등)
        if File.exist?("Gemfile")
          gemfile = File.read("Gemfile")
          # gem "rails", "~> 8.0" 형식
          if match = gemfile.match(/gem\s+["']rails["'],\s*["']~>\s*(\d+\.\d+)["']/)
            return "#{match[1]}.0"
          end
          # github: "rails/rails" (edge) - Rails 8+ 가정
          if gemfile.match?(/gem\s+["']rails["'].*github:\s*["']rails\/rails["']/)
            return "8.0.0 (edge)"
          end
        end

        nil
      end

      def add_solid_cable_gem
        puts "📦 Gemfile에 solid_cable을 추가합니다...".colorize(:yellow)

        gemfile = File.read("Gemfile")

        if gemfile.include?("solid_cable")
          puts "   ℹ️  solid_cable이 이미 존재합니다.".colorize(:yellow)
          return
        end

        # solid_cable gem 추가
        if gemfile.include?("solid_queue")
          # solid_queue 다음에 추가
          gemfile.gsub!(/^gem ["']solid_queue["'].*$/) do |match|
            "#{match}\ngem \"solid_cable\""
          end
        elsif gemfile.match?(/^gem ["']rails["']/)
          # rails gem 다음에 추가
          gemfile.gsub!(/^gem ["']rails["'].*$/) do |match|
            "#{match}\n\n# Solid Cable - SQLite 기반 Action Cable 어댑터\ngem \"solid_cable\""
          end
        else
          # 파일 끝에 추가
          gemfile += "\n# Solid Cable - SQLite 기반 Action Cable 어댑터\ngem \"solid_cable\"\n"
        end

        File.write("Gemfile", gemfile)
        puts "   ✅ Gemfile에 solid_cable을 추가했습니다.".colorize(:green)
      end

      def update_database_yml
        puts "🗄️  database.yml을 업데이트합니다...".colorize(:yellow)

        database_yml_path = "config/database.yml"
        content = File.read(database_yml_path)

        # 이미 cable 설정이 있는지 확인
        if content.include?("cable:") || content.include?("cable_production:")
          puts "   ℹ️  cable 데이터베이스가 이미 설정되어 있습니다.".colorize(:yellow)
          return
        end

        # 기존 database.yml 파싱
        # production 설정에 cable DB 추가
        new_content = generate_database_yml(content)

        File.write(database_yml_path, new_content)
        puts "   ✅ database.yml에 cable 데이터베이스를 추가했습니다.".colorize(:green)
      end

      def generate_database_yml(original_content)
        # 기존 내용 유지하면서 cable DB 추가
        lines = original_content.lines

        # production 섹션 찾기
        production_index = lines.find_index { |line| line.match?(/^production:/) }

        if production_index
          # production 섹션 끝 찾기
          next_section_index = lines[(production_index + 1)..].find_index { |line| line.match?(/^\w+:/) }
          insert_index = next_section_index ? production_index + 1 + next_section_index : lines.length

          cable_config = <<~YAML

            # Solid Cable용 별도 데이터베이스 (WAL 모드 최적화)
            cable_production:
              <<: *default
              database: storage/db/cable_production.sqlite3
              migrations_paths: db/cable_migrate
          YAML

          lines.insert(insert_index, cable_config)
        end

        # development/test에도 추가
        dev_index = lines.find_index { |line| line.match?(/^development:/) }
        if dev_index
          next_section_index = lines[(dev_index + 1)..].find_index { |line| line.match?(/^\w+:/) }
          insert_index = next_section_index ? dev_index + 1 + next_section_index : lines.length

          cable_config = <<~YAML

            cable_development:
              <<: *default
              database: storage/db/cable_development.sqlite3
              migrations_paths: db/cable_migrate
          YAML

          lines.insert(insert_index, cable_config)
        end

        test_index = lines.find_index { |line| line.match?(/^test:/) }
        if test_index
          next_section_index = lines[(test_index + 1)..].find_index { |line| line.match?(/^\w+:/) }
          insert_index = next_section_index ? test_index + 1 + next_section_index : lines.length

          cable_config = <<~YAML

            cable_test:
              <<: *default
              database: storage/db/cable_test.sqlite3
              migrations_paths: db/cable_migrate
          YAML

          lines.insert(insert_index, cable_config)
        end

        lines.join
      end

      def update_cable_yml
        puts "📡 cable.yml을 업데이트합니다...".colorize(:yellow)

        cable_yml_path = "config/cable.yml"

        # Development는 async (단일 프로세스), Production은 solid_cable
        cable_config = <<~YAML
          # Solid Cable 설정 (SQLite 기반 Action Cable)
          # Development: async 어댑터 (단일 프로세스, 콘솔 디버깅 용이)
          # Production: solid_cable (polling_interval: 25ms, Redis 수준 RTT)

          development:
            adapter: async

          test:
            adapter: test

          production:
            adapter: solid_cable
            connects_to:
              database:
                writing: cable
            polling_interval: 0.025.seconds
            message_retention: 1.hour
        YAML

        # 기존 파일 백업
        if File.exist?(cable_yml_path)
          backup_path = "#{cable_yml_path}.backup"
          FileUtils.cp(cable_yml_path, backup_path)
          puts "   📋 기존 cable.yml을 #{backup_path}로 백업했습니다.".colorize(:gray)
        end

        File.write(cable_yml_path, cable_config)
        puts "   ✅ cable.yml을 Solid Cable 설정으로 업데이트했습니다.".colorize(:green)
      end

      def create_sqlite_initializer
        puts "⚡ SQLite 최적화 initializer를 생성합니다...".colorize(:yellow)

        initializer_path = "config/initializers/solid_cable_sqlite.rb"

        if File.exist?(initializer_path)
          puts "   ℹ️  initializer가 이미 존재합니다.".colorize(:yellow)
          return
        end

        initializer_content = <<~RUBY
          # frozen_string_literal: true

          # Solid Cable SQLite 최적화 설정
          # - WAL 모드: 읽기/쓰기 동시성 향상 (폴링과 브로드캐스트 동시 처리)
          # - synchronous=NORMAL: 쓰기 성능 향상 (약간의 안정성 트레이드오프)

          Rails.application.config.after_initialize do
            # Cable 데이터베이스에 WAL 모드 설정
            if defined?(SolidCable) && ActiveRecord::Base.configurations.configs_for(name: "cable")
              ActiveRecord::Base.connected_to(role: :writing, shard: :cable) do
                connection = ActiveRecord::Base.connection

                # WAL 모드 활성화 - 읽기/쓰기 동시 처리 가능
                connection.execute("PRAGMA journal_mode=WAL")

                # synchronous=NORMAL - fsync 횟수 감소로 쓰기 성능 향상
                connection.execute("PRAGMA synchronous=NORMAL")

                # 캐시 크기 증가 (기본값의 2배)
                connection.execute("PRAGMA cache_size=4000")

                Rails.logger.info "[SolidCable] SQLite WAL 모드 최적화 적용됨"
              rescue ActiveRecord::ConnectionNotEstablished
                # 마이그레이션 전에는 연결이 없을 수 있음
                Rails.logger.debug "[SolidCable] Cable 데이터베이스 연결 대기 중..."
              end
            end
          end
        RUBY

        FileUtils.mkdir_p("config/initializers")
        File.write(initializer_path, initializer_content)
        puts "   ✅ config/initializers/solid_cable_sqlite.rb를 생성했습니다.".colorize(:green)
      end

      def run_bundle_install
        puts "📦 bundle install을 실행합니다...".colorize(:yellow)

        if system("bundle install")
          puts "   ✅ bundle install 완료".colorize(:green)
        else
          puts "   ❌ bundle install 실패".colorize(:red)
          puts "   수동으로 bundle install을 실행해주세요.".colorize(:yellow)
          exit 1
        end
      end

      def install_solid_cable
        puts "🔌 Solid Cable을 설치합니다...".colorize(:yellow)

        # solid_cable:install 태스크가 있는지 확인
        if system("bin/rails solid_cable:install")
          puts "   ✅ Solid Cable 설치 완료".colorize(:green)
        else
          puts "   ⚠️  solid_cable:install 태스크를 찾을 수 없습니다.".colorize(:yellow)
          puts "   마이그레이션 파일을 직접 생성합니다...".colorize(:yellow)
          create_cable_migration
        end
      end

      def create_cable_migration
        # db/cable_migrate 디렉토리 생성
        FileUtils.mkdir_p("db/cable_migrate")

        timestamp = Time.now.strftime("%Y%m%d%H%M%S")
        migration_path = "db/cable_migrate/#{timestamp}_create_solid_cable_messages.rb"

        migration_content = <<~RUBY
          class CreateSolidCableMessages < ActiveRecord::Migration[7.2]
            def change
              create_table :solid_cable_messages do |t|
                t.binary :channel, null: false, limit: 1024
                t.binary :payload, null: false, limit: 536870912
                t.datetime :created_at, null: false
                t.integer :channel_hash, null: false, limit: 8

                t.index :channel
                t.index :channel_hash
                t.index :created_at
              end
            end
          end
        RUBY

        File.write(migration_path, migration_content)
        puts "   ✅ 마이그레이션 파일 생성: #{migration_path}".colorize(:green)
      end

      def run_migrations
        puts "🗄️  데이터베이스를 준비합니다...".colorize(:yellow)

        # storage 디렉토리 생성
        FileUtils.mkdir_p("storage")

        # db:prepare는 마이그레이션 + 스키마 로드를 모두 처리
        if system("bin/rails db:prepare")
          puts "   ✅ 데이터베이스 준비 완료".colorize(:green)
        else
          puts "   ⚠️  데이터베이스 준비 실패".colorize(:yellow)
          puts "   수동으로 bin/rails db:prepare를 실행해주세요.".colorize(:yellow)
        end
      end

      def create_documentation
        puts "📄 설정 문서를 생성합니다...".colorize(:yellow)

        FileUtils.mkdir_p("docs")
        doc_path = "docs/solid-cable-sqlite-setup.md"

        if File.exist?(doc_path)
          puts "   ℹ️  문서가 이미 존재합니다.".colorize(:yellow)
          return
        end

        # 템플릿 파일에서 문서 내용 읽기
        template_path = File.expand_path("../../templates/solid-cable-sqlite-setup.md", __FILE__)
        doc_content = File.read(template_path)

        File.write(doc_path, doc_content)
        puts "   ✅ docs/solid-cable-sqlite-setup.md를 생성했습니다.".colorize(:green)
      end
    end
  end
end
