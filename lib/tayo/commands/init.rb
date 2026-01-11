# frozen_string_literal: true

require "colorize"
require_relative "../dockerfile_modifier"

module Tayo
  module Commands
    class Init
      def execute
        puts "🏠 Tayo v#{Tayo::VERSION} 초기화를 시작합니다...".colorize(:green)

        unless rails_project?
          puts "❌ Rails 프로젝트가 아닙니다. Rails 프로젝트 루트에서 실행해주세요.".colorize(:red)
          return
        end
        commit_initial_state
        check_orbstack
        create_welcome_page
        clear_docker_cache
        ensure_dockerfile_exists
        commit_changes
        puts "✅ Tayo가 성공적으로 설정되었습니다!".colorize(:green)
      end

      private

      def rails_project?
        File.exist?("Gemfile") && File.exist?("config/application.rb")
      end

      def check_orbstack
        puts "🐳 OrbStack 상태를 확인합니다...".colorize(:yellow)

        # OrbStack 실행 상태 확인
        orbstack_running = system("pgrep -x OrbStack > /dev/null 2>&1")

        if orbstack_running
          puts "✅ OrbStack이 실행 중입니다.".colorize(:green)
        else
          puts "🚀 OrbStack을 시작합니다...".colorize(:yellow)

          # OrbStack 실행
          if system("open -a OrbStack")
            puts "✅ OrbStack이 시작되었습니다.".colorize(:green)

            # OrbStack이 완전히 시작될 때까지 잠시 대기
            print "Docker 서비스가 준비될 때까지 대기 중".colorize(:yellow)
            5.times do
              sleep 1
              print ".".colorize(:yellow)
            end
            puts ""

            # Docker가 준비되었는지 확인
            if system("docker ps > /dev/null 2>&1")
              puts "✅ Docker가 준비되었습니다.".colorize(:green)
            else
              puts "⚠️  Docker가 아직 준비되지 않았습니다. 잠시 후 다시 시도해주세요.".colorize(:yellow)
            end
          else
            puts "❌ OrbStack을 시작할 수 없습니다.".colorize(:red)
            puts "OrbStack이 설치되어 있는지 확인해주세요.".colorize(:yellow)
            puts "https://orbstack.dev 에서 다운로드할 수 있습니다.".colorize(:cyan)
          end
        end
      end

      def ensure_dockerfile_exists
        unless File.exist?("Dockerfile")
          puts "🐳 Dockerfile이 없습니다. 기본 Dockerfile을 생성합니다...".colorize(:yellow)

          # Rails 7의 기본 Dockerfile 생성
          if system("rails app:update:bin")
            system("./bin/rails generate dockerfile")
            puts "✅ Dockerfile이 생성되었습니다.".colorize(:green)
          else
            puts "⚠️  Dockerfile 생성에 실패했습니다. 수동으로 생성해주세요.".colorize(:yellow)
            puts "   다음 명령어를 실행하세요: ./bin/rails generate dockerfile".colorize(:cyan)
            return
          end
        else
          puts "✅ Dockerfile이 이미 존재합니다.".colorize(:green)
        end
      end

      def create_welcome_page
        # Welcome 컨트롤러가 이미 있는지 확인
        if File.exist?("app/controllers/welcome_controller.rb")
          puts "ℹ️  Welcome 페이지가 이미 존재합니다.".colorize(:yellow)
          @welcome_page_created = false
          return
        end

        puts "🎨 Welcome 페이지를 생성합니다...".colorize(:yellow)

        # Welcome 컨트롤러 생성 시도
        unless system("rails generate controller Welcome index --skip-routes --no-helper --no-assets")
          puts "   ⚠️  rails generate 실패. 수동으로 파일을 생성합니다.".colorize(:yellow)
          # 디렉토리와 컨트롤러 파일 직접 생성
          FileUtils.mkdir_p("app/controllers")
          FileUtils.mkdir_p("app/views/welcome")

          controller_content = <<~RUBY
            class WelcomeController < ApplicationController
              def index
              end
            end
          RUBY
          File.write("app/controllers/welcome_controller.rb", controller_content)
        end

        # 프로젝트 이름 가져오기
        project_name = File.basename(Dir.pwd).gsub(/[-_]/, ' ').split.map(&:capitalize).join(' ')

        # Welcome 페이지 HTML 생성
        welcome_html = <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <title>#{project_name} - Welcome</title>
            <meta name="viewport" content="width=device-width,initial-scale=1">
            <style>
              * { margin: 0; padding: 0; box-sizing: border-box; }
              body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                min-height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
                color: white;
              }
              .container {
                text-align: center;
                padding: 2rem;
                max-width: 800px;
                animation: fadeIn 1s ease-out;
              }
              h1 {
                font-size: 4rem;
                margin-bottom: 1rem;
                text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
                animation: slideDown 0.8s ease-out;
              }
              .subtitle {
                font-size: 1.5rem;
                margin-bottom: 3rem;
                opacity: 0.9;
                animation: slideUp 0.8s ease-out 0.2s both;
              }
              .info-grid {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                gap: 2rem;
                margin-top: 3rem;
              }
              .info-card {
                background: rgba(255,255,255,0.1);
                backdrop-filter: blur(10px);
                padding: 2rem;
                border-radius: 10px;
                border: 1px solid rgba(255,255,255,0.2);
                animation: fadeIn 0.8s ease-out 0.4s both;
              }
              .info-card h3 {
                font-size: 1.2rem;
                margin-bottom: 0.5rem;
              }
              .info-card p {
                opacity: 0.8;
                font-size: 0.9rem;
              }
              .deploy-badge {
                display: inline-block;
                background: rgba(255,255,255,0.2);
                padding: 0.5rem 1rem;
                border-radius: 20px;
                margin-top: 2rem;
                font-size: 0.9rem;
                animation: pulse 2s infinite;
              }
              @keyframes fadeIn {
                from { opacity: 0; transform: translateY(20px); }
                to { opacity: 1; transform: translateY(0); }
              }
              @keyframes slideDown {
                from { opacity: 0; transform: translateY(-30px); }
                to { opacity: 1; transform: translateY(0); }
              }
              @keyframes slideUp {
                from { opacity: 0; transform: translateY(30px); }
                to { opacity: 1; transform: translateY(0); }
              }
              @keyframes pulse {
                0%, 100% { opacity: 1; }
                50% { opacity: 0.8; }
              }
            </style>
          </head>
          <body>
            <div class="container">
              <h1>🏠 #{project_name}</h1>
              <p class="subtitle">Welcome to your Tayo-powered Rails application!</p>

              <div class="info-grid">
                <div class="info-card">
                  <h3>📦 Container Ready</h3>
                  <p>Your app is configured for container deployment</p>
                </div>
                <div class="info-card">
                  <h3>🚀 GitHub Integration</h3>
                  <p>Ready to push to GitHub Container Registry</p>
                </div>
                <div class="info-card">
                  <h3>☁️ Cloudflare DNS</h3>
                  <p>Domain management simplified</p>
                </div>
              </div>

              <div class="deploy-badge">
                Deployed with Tayo 🎉
              </div>
            </div>
          </body>
          </html>
        HTML

        # Welcome 뷰 파일에 저장
        welcome_view_path = "app/views/welcome/index.html.erb"
        File.write(welcome_view_path, welcome_html)

        # routes.rb 업데이트
        routes_file = "config/routes.rb"
        routes_content = File.read(routes_file)

        # root 경로 설정 - welcome#index가 이미 있는지 확인
        unless routes_content.include?("welcome#index")
          if routes_content.match?(/^\s*root\s+/)
            # 기존 root 설정이 있으면 교체
            routes_content.gsub!(/^\s*root\s+.*$/, "  root 'welcome#index'")
          else
            # root 설정이 없으면 추가
            routes_content.gsub!(/Rails\.application\.routes\.draw do\s*\n/, "Rails.application.routes.draw do\n  root 'welcome#index'\n")
          end

          File.write(routes_file, routes_content)
          puts "   ✅ routes.rb에 root 경로를 설정했습니다.".colorize(:green)
        else
          puts "   ℹ️  routes.rb에 welcome#index가 이미 설정되어 있습니다.".colorize(:yellow)
        end

        puts "✅ Welcome 페이지가 생성되었습니다!".colorize(:green)
        puts "   경로: /".colorize(:gray)
        puts "   컨트롤러: app/controllers/welcome_controller.rb".colorize(:gray)
        puts "   뷰: app/views/welcome/index.html.erb".colorize(:gray)

        @welcome_page_created = true
      end

      def commit_initial_state
        # Git 저장소인지 확인
        unless Dir.exist?(".git")
          puts "⚠️  Git 저장소가 아닙니다. 커밋을 건너뜁니다.".colorize(:yellow)
          return
        end

        puts "📝 초기 상태를 Git에 커밋합니다...".colorize(:yellow)

        # Git 상태 확인
        git_status = `git status --porcelain`

        if git_status.strip.empty?
          puts "ℹ️  커밋할 변경사항이 없습니다.".colorize(:yellow)
          return
        end

        # 변경사항 스테이징
        system("git add .")

        # 커밋
        commit_message = "Save current state before Tayo initialization"
        if system("git commit -m '#{commit_message}'")
          puts "✅ 초기 상태가 커밋되었습니다.".colorize(:green)
          puts "   커밋 메시지: #{commit_message}".colorize(:gray)
        else
          puts "⚠️  커밋에 실패했습니다.".colorize(:yellow)
        end
      end

      def commit_changes
        # Git 저장소인지 확인
        unless Dir.exist?(".git")
          puts "⚠️  Git 저장소가 아닙니다. 커밋을 건너뜁니다.".colorize(:yellow)
          return
        end

        puts "📝 Tayo 설정 완료 상태를 Git에 커밋합니다...".colorize(:yellow)

        # Git 상태 확인
        git_status = `git status --porcelain`

        if git_status.strip.empty?
          puts "ℹ️  커밋할 변경사항이 없습니다.".colorize(:yellow)
          return
        end

        # 변경사항 스테이징
        system("git add .")

        # 커밋
        commit_message = "Complete Tayo initialization with Welcome page and Docker setup"
        if system("git commit -m '#{commit_message}'")
          puts "✅ Tayo 설정이 완료되어 커밋되었습니다.".colorize(:green)
          puts "   커밋 메시지: #{commit_message}".colorize(:gray)
        else
          puts "⚠️  커밋에 실패했습니다.".colorize(:yellow)
        end
      end

      def clear_docker_cache
        puts "🧹 Docker 캐시를 정리합니다...".colorize(:yellow)

        # Docker system prune
        if system("docker system prune -f > /dev/null 2>&1")
          puts "✅ Docker 시스템 캐시가 정리되었습니다.".colorize(:green)
        else
          puts "⚠️  Docker 시스템 정리에 실패했습니다.".colorize(:yellow)
        end

        # Kamal build cache clear
        if File.exist?("config/deploy.yml")
          puts "🚢 Kamal 빌드 캐시를 정리합니다...".colorize(:yellow)
          if system("kamal build --clear-cache > /dev/null 2>&1")
            puts "✅ Kamal 빌드 캐시가 정리되었습니다.".colorize(:green)
          else
            puts "⚠️  Kamal 빌드 캐시 정리에 실패했습니다.".colorize(:yellow)
          end
        end
      end
    end
  end
end