# frozen_string_literal: true

require "colorize"
require "json"
require "git"
require "yaml"
require "tty-prompt"

module Tayo
  module Commands
    class Gh
      def execute
        puts "🚀 GitHub 저장소 및 컨테이너 레지스트리 설정을 시작합니다...".colorize(:green)

        unless rails_project?
          puts "❌ Rails 프로젝트가 아닙니다. Rails 프로젝트 루트에서 실행해주세요.".colorize(:red)
          return
        end

        puts "\n[1/7] GitHub CLI 설치 확인".colorize(:blue)
        check_github_cli
        
        puts "\n[2/7] GitHub 로그인 확인".colorize(:blue)
        check_github_auth
        
        puts "\n[3/7] 컨테이너 레지스트리 권한 확인".colorize(:blue)
        check_container_registry_permission
        
        puts "\n[4/7] Git 저장소 초기화".colorize(:blue)
        init_git_repo
        
        puts "\n[5/7] GitHub 저장소 생성".colorize(:blue)
        create_github_repository
        
        puts "\n[6/7] 컨테이너 레지스트리 설정".colorize(:blue)
        create_container_registry
        
        puts "\n[7/7] 배포 설정 파일 생성".colorize(:blue)
        create_deploy_config

        puts "\n🎉 모든 설정이 완료되었습니다!".colorize(:green)
        puts "\n다음 정보가 설정되었습니다:".colorize(:yellow)
        puts "• GitHub 저장소: https://github.com/#{@username}/#{@repo_name}".colorize(:cyan)
        puts "• Container Registry: #{@registry_url}".colorize(:cyan)
        puts "• 배포 설정: config/deploy.yml".colorize(:cyan)
      end

      private

      def rails_project?
        File.exist?("Gemfile") && File.exist?("config/application.rb")
      end

      def check_github_cli
        if system("gh --version", out: File::NULL, err: File::NULL)
          puts "✅ GitHub CLI가 이미 설치되어 있습니다.".colorize(:green)
        else
          puts "📦 GitHub CLI를 설치합니다...".colorize(:yellow)
          system("brew install gh")
          puts "✅ GitHub CLI 설치 완료.".colorize(:green)
        end
      end

      def check_github_auth
        auth_status = `gh auth status 2>&1`
        
        unless $?.success?
          puts "🔑 GitHub 로그인이 필요합니다.".colorize(:yellow)
          puts "다음 명령어를 실행하여 로그인해주세요:".colorize(:yellow)
          puts "gh auth login".colorize(:cyan)
          exit 1
        end
        
        # 토큰 만료 확인
        if auth_status.include?("Token has expired") || auth_status.include?("authentication failed")
          puts "⚠️  GitHub 토큰이 만료되었습니다.".colorize(:yellow)
          puts "다시 로그인해주세요:".colorize(:yellow)
          puts "gh auth login".colorize(:cyan)
          exit 1
        end
        
        puts "✅ GitHub에 로그인되어 있습니다.".colorize(:green)
      end

      def check_container_registry_permission
        scopes = `gh auth status -t 2>&1`
        
        # 토큰 만료 확인 (권한 체크 시에도)
        if scopes.include?("Token has expired") || scopes.include?("authentication failed")
          puts "⚠️  GitHub 토큰이 만료되었습니다.".colorize(:yellow)
          puts "다시 로그인해주세요:".colorize(:yellow)
          puts "gh auth login".colorize(:cyan)
          exit 1
        end
        
        unless scopes.include?("write:packages") || scopes.include?("admin:packages")
          puts "⚠️  컨테이너 레지스트리 권한이 없습니다.".colorize(:yellow)
          puts "\nTayo가 정상 작동하기 위해 다음 권한들이 필요합니다:".colorize(:yellow)
          puts "• repo - GitHub 저장소 생성 및 관리".colorize(:yellow)
          puts "• read:org - 조직 정보 읽기".colorize(:yellow)
          puts "• write:packages - Docker 이미지를 Container Registry에 푸시".colorize(:yellow)
          puts "\n토큰 생성 페이지를 엽니다...".colorize(:cyan)
          
          project_name = File.basename(Dir.pwd)
          token_description = "Tayo%20-%20#{project_name}"
          token_url = "https://github.com/settings/tokens/new?scopes=repo,read:org,write:packages&description=#{token_description}"
          system("open '#{token_url}'")
          
          puts "\n✅ 브라우저에서 GitHub 토큰 생성 페이지가 열렸습니다.".colorize(:green)
          puts "📌 필요한 권한들이 이미 체크되어 있습니다:".colorize(:green)
          puts "   • repo - 저장소 생성 및 관리".colorize(:gray)
          puts "   • read:org - 조직 정보 읽기".colorize(:gray)
          puts "   • write:packages - Container Registry 접근".colorize(:gray)
          
          puts "\n다음 단계를 따라주세요:".colorize(:yellow)
          puts "1. 페이지 하단의 'Generate token' 버튼을 클릭하세요".colorize(:cyan)
          puts "2. 생성된 토큰을 복사하세요".colorize(:cyan)
          puts "3. 아래에 토큰을 붙여넣으세요:".colorize(:cyan)
          
          print "\n토큰 입력: ".colorize(:yellow)
          token = STDIN.gets.chomp
          
          if token.empty?
            puts "❌ 토큰이 입력되지 않았습니다.".colorize(:red)
            exit 1
          end
          
          # 토큰을 임시 파일에 저장하고 gh auth login 실행
          require 'tempfile'
          Tempfile.create('github_token') do |f|
            f.write(token)
            f.flush
            
            puts "\n🔐 GitHub에 로그인 중...".colorize(:yellow)
            if system("gh auth login --with-token < #{f.path}")
              puts "✅ GitHub 로그인에 성공했습니다!".colorize(:green)
              puts "\n다시 'tayo gh' 명령을 실행해주세요.".colorize(:cyan)
            else
              puts "❌ GitHub 로그인에 실패했습니다.".colorize(:red)
            end
          end
          
          exit 0
        end
        
        puts "✅ 컨테이너 레지스트리 권한이 확인되었습니다.".colorize(:green)
      end

      def init_git_repo
        unless Dir.exist?(".git")
          Git.init(".")
          puts "✅ Git 저장소를 초기화했습니다.".colorize(:green)
        else
          puts "ℹ️  Git 저장소가 이미 초기화되어 있습니다.".colorize(:yellow)
        end

        git = Git.open(".")
        
        # HEAD 커밋이 있는지 확인
        has_commits = begin
          git.log.count > 0
        rescue Git::GitExecuteError
          false
        end
        
        # git status로 변경사항 확인 (HEAD가 없으면 다른 방법 사용)
        has_changes = if has_commits
          git.status.untracked.any? || git.status.changed.any?
        else
          # HEAD가 없을 때는 워킹 디렉토리에 파일이 있는지 확인
          Dir.glob("*", File::FNM_DOTMATCH).reject { |f| f == "." || f == ".." || f == ".git" }.any?
        end
        
        if has_changes
          git.add(all: true)
          git.commit("init")
          puts "✅ 초기 커밋을 생성했습니다.".colorize(:green)
        else
          puts "ℹ️  커밋할 변경사항이 없습니다.".colorize(:yellow)
        end
      end

      def create_github_repository
        repo_name = File.basename(Dir.pwd)
        username = `gh api user -q .login`.strip
        
        # 조직 목록 가져오기
        orgs_json = `gh api user/orgs -q '.[].login' 2>/dev/null`
        orgs = orgs_json.strip.split("\n").reject(&:empty?)
        
        owner = username
        
        if orgs.any?
          prompt = TTY::Prompt.new
          choices = ["#{username} (개인 계정)"] + orgs.map { |org| "#{org} (조직)" }
          
          selection = prompt.select("🏢 저장소를 생성할 위치를 선택하세요:", choices)
          
          if selection != "#{username} (개인 계정)"
            owner = selection.split(" ").first
          end
        end
        
        # 저장소 존재 여부 확인
        repo_exists = system("gh repo view #{owner}/#{repo_name}", out: File::NULL, err: File::NULL)
        
        if repo_exists
          puts "ℹ️  GitHub 저장소가 이미 존재합니다: https://github.com/#{owner}/#{repo_name}".colorize(:yellow)
          @repo_name = repo_name
          @username = owner
        else
          create_cmd = if owner == username
            "gh repo create #{repo_name} --private --source=. --remote=origin --push"
          else
            "gh repo create #{owner}/#{repo_name} --private --source=. --remote=origin --push"
          end
          
          result = system(create_cmd)
          
          if result
            puts "✅ GitHub 저장소를 생성했습니다: https://github.com/#{owner}/#{repo_name}".colorize(:green)
            @repo_name = repo_name
            @username = owner
          else
            puts "❌ GitHub 저장소 생성에 실패했습니다.".colorize(:red)
            exit 1
          end
        end
      end

      def create_container_registry
        # Docker 이미지 태그는 소문자여야 함
        registry_url = "ghcr.io/#{@username.downcase}/#{@repo_name.downcase}"
        @registry_url = registry_url
        
        puts "✅ 컨테이너 레지스트리가 설정되었습니다.".colorize(:green)
        puts "   URL: #{registry_url}".colorize(:gray)
        puts "   ℹ️  컨테이너 레지스트리는 첫 이미지 푸시 시 자동으로 생성됩니다.".colorize(:gray)
        
        # Docker로 GitHub Container Registry에 로그인
        puts "\n🐳 Docker로 GitHub Container Registry에 로그인합니다...".colorize(:yellow)
        
        # 현재 GitHub 토큰 가져오기
        token = `gh auth token`.strip
        
        if token.empty?
          puts "❌ GitHub 토큰을 가져올 수 없습니다.".colorize(:red)
          return
        end
        
        # Docker login 실행
        login_cmd = "echo #{token} | docker login ghcr.io -u #{@username} --password-stdin"
        
        if system(login_cmd)
          puts "✅ Docker 로그인에 성공했습니다!".colorize(:green)
          puts "   Registry: ghcr.io".colorize(:gray)
          puts "   Username: #{@username}".colorize(:gray)
        else
          puts "❌ Docker 로그인에 실패했습니다.".colorize(:red)
          puts "   수동으로 다음 명령을 실행해주세요:".colorize(:yellow)
          puts "   docker login ghcr.io".colorize(:cyan)
        end
      end

      def create_deploy_config
        config_dir = "config"
        Dir.mkdir(config_dir) unless Dir.exist?(config_dir)
        
        if File.exist?("config/deploy.yml")
          puts "ℹ️  기존 config/deploy.yml 파일을 업데이트합니다.".colorize(:yellow)
          update_kamal_config
        else
          puts "✅ config/deploy.yml 파일을 생성했습니다.".colorize(:green)
          create_tayo_config
        end
      end

      private

      def update_kamal_config
        content = File.read("config/deploy.yml")
        
        # 이미지 설정 업데이트 (ghcr.io 중복 제거)
        # @registry_url은 이미 ghcr.io를 포함하고 있으므로, 그대로 사용
        content.gsub!(/^image:\s+.*$/, "image: #{@registry_url}")
        
        # registry 섹션 업데이트
        if content.include?("registry:")
          # 기존 registry 섹션 수정
          # server 라인이 주석처리되어 있는지 확인
          if content.match?(/^\s*#\s*server:/)
            content.gsub!(/^\s*#\s*server:\s*.*$/, "  server: ghcr.io")
          elsif content.match?(/^\s*server:/)
            content.gsub!(/^\s*server:\s*.*$/, "  server: ghcr.io")
          else
            # server 라인이 없으면 username 위에 추가
            content.gsub!(/(\s*username:\s+)/, "  server: ghcr.io\n\\1")
          end
          # username도 소문자로 변환
          content.gsub!(/^\s*username:\s+.*$/, "  username: #{@username.downcase}")
        else
          # registry 섹션 추가
          registry_config = "\n# Container registry configuration\nregistry:\n  server: ghcr.io\n  username: #{@username.downcase}\n  password:\n    - KAMAL_REGISTRY_PASSWORD\n"
          content.gsub!(/^# Credentials for your image host\.\nregistry:.*?^$/m, registry_config)
        end
        
        File.write("config/deploy.yml", content)
        
        # GitHub 토큰을 Kamal secrets 파일에 설정
        setup_kamal_secrets
        
        puts "✅ Container Registry 설정이 업데이트되었습니다:".colorize(:green)
        puts "   • 이미지: #{@registry_url}".colorize(:gray)
        puts "   • 레지스트리 서버: ghcr.io".colorize(:gray)
        puts "   • 사용자명: #{@username}".colorize(:gray)
      end
      
      def setup_kamal_secrets
        # .kamal 디렉토리 생성
        Dir.mkdir(".kamal") unless Dir.exist?(".kamal")
        
        # 현재 GitHub 토큰 가져오기
        token_output = `gh auth token 2>/dev/null`
        
        if $?.success? && !token_output.strip.empty?
          token = token_output.strip
          secrets_file = ".kamal/secrets"
          
          # 기존 secrets 파일 읽기 (있다면)
          existing_content = File.exist?(secrets_file) ? File.read(secrets_file) : ""
          
          # KAMAL_REGISTRY_PASSWORD가 이미 있는지 확인
          if existing_content.include?("KAMAL_REGISTRY_PASSWORD")
            # 기존 값 업데이트
            updated_content = existing_content.gsub(/^KAMAL_REGISTRY_PASSWORD=.*$/, "KAMAL_REGISTRY_PASSWORD=#{token}")
          else
            # 새로 추가
            updated_content = existing_content.empty? ? "KAMAL_REGISTRY_PASSWORD=#{token}\n" : "#{existing_content.chomp}\nKAMAL_REGISTRY_PASSWORD=#{token}\n"
          end
          
          File.write(secrets_file, updated_content)
          puts "✅ GitHub 토큰이 .kamal/secrets에 설정되었습니다.".colorize(:green)
          
          # .gitignore에 secrets 파일 추가
          add_to_gitignore(".kamal/secrets")
        else
          puts "⚠️  GitHub 토큰을 가져올 수 없습니다. 수동으로 설정해주세요:".colorize(:yellow)
          puts "   echo 'KAMAL_REGISTRY_PASSWORD=your_github_token' >> .kamal/secrets".colorize(:cyan)
        end
      end
      
      def add_to_gitignore(file_path)
        gitignore_file = ".gitignore"
        
        if File.exist?(gitignore_file)
          content = File.read(gitignore_file)
          unless content.include?(file_path)
            File.write(gitignore_file, "#{content.chomp}\n#{file_path}\n")
            puts "✅ .gitignore에 #{file_path}를 추가했습니다.".colorize(:green)
          end
        else
          File.write(gitignore_file, "#{file_path}\n")
          puts "✅ .gitignore 파일을 생성하고 #{file_path}를 추가했습니다.".colorize(:green)
        end
      end

      def create_tayo_config
        deploy_config = {
          "production" => {
            "registry" => @registry_url,
            "repository" => "https://github.com/#{@username}/#{@repo_name}",
            "server" => {
              "host" => "your-home-server.local",
              "user" => "deploy",
              "port" => 22
            },
            "environment" => {
              "RAILS_ENV" => "production",
              "RAILS_MASTER_KEY" => "your-master-key"
            }
          }
        }
        
        File.write("config/deploy.yml", deploy_config.to_yaml)
        puts "   ⚠️  서버 정보와 환경 변수를 설정해주세요.".colorize(:yellow)
      end
    end
  end
end