# frozen_string_literal: true

require "colorize"
require "fileutils"
require "yaml"
require "erb"

module Tayo
  module Proxy
    class TraefikConfig
      TRAEFIK_CONFIG_DIR = File.expand_path("~/.tayo/traefik")

      def initialize
        @docker = DockerManager.new
      end

      def setup(domains, email = nil)
        puts "\n⚙️  Traefik을 설정합니다...".colorize(:yellow)

        # 설정 디렉토리 생성
        setup_directories

        # 이메일 주소 입력 (Let's Encrypt용)
        email ||= get_email_for_acme

        # 설정 파일 생성
        create_docker_compose(email)
        create_traefik_config(email)
        create_dynamic_config(domains)

        # Traefik 시작
        ensure_running

        # 라우팅 설정
        configure_routes(domains)

        puts "✅ Traefik 설정이 완료되었습니다.".colorize(:green)
      end

      private

      def setup_directories
        FileUtils.mkdir_p(TRAEFIK_CONFIG_DIR)
        FileUtils.mkdir_p(File.join(TRAEFIK_CONFIG_DIR, "config"))

        # acme.json 파일 생성 및 권한 설정
        acme_file = File.join(TRAEFIK_CONFIG_DIR, "acme.json")
        unless File.exist?(acme_file)
          File.write(acme_file, "{}")
          File.chmod(0600, acme_file)
        end
      end

      def get_email_for_acme
        prompt = TTY::Prompt.new

        # 저장된 이메일 확인
        email_file = File.join(TRAEFIK_CONFIG_DIR, ".email")
        if File.exist?(email_file)
          saved_email = File.read(email_file).strip
          if prompt.yes?("저장된 이메일을 사용하시겠습니까? (#{saved_email})")
            return saved_email
          end
        end

        # 새 이메일 입력
        email = prompt.ask("Let's Encrypt 인증서용 이메일 주소를 입력하세요:") do |q|
          q.validate(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i, "올바른 이메일 형식을 입력해주세요")
        end

        # 이메일 저장
        File.write(email_file, email)
        email
      end

      def create_docker_compose(email)
        compose_content = <<~YAML
          version: '3.8'

          services:
            traefik:
              image: traefik:v3.0
              container_name: traefik
              restart: unless-stopped
              security_opt:
                - no-new-privileges:true
              networks:
                - traefik-net
              ports:
                - "80:80"
                - "443:443"
                - "8080:8080"  # 대시보드
              extra_hosts:
                - "host.docker.internal:host-gateway"
              volumes:
                - /var/run/docker.sock:/var/run/docker.sock:ro
                - #{TRAEFIK_CONFIG_DIR}/config/traefik.yml:/etc/traefik/traefik.yml:ro
                - #{TRAEFIK_CONFIG_DIR}/config/dynamic.yml:/etc/traefik/dynamic.yml:ro
                - #{TRAEFIK_CONFIG_DIR}/acme.json:/acme.json
              labels:
                - "traefik.enable=true"
                - "traefik.http.routers.dashboard.rule=Host(`traefik.localhost`)"
                - "traefik.http.routers.dashboard.service=api@internal"
                - "traefik.http.routers.dashboard.middlewares=auth"
                - "traefik.http.middlewares.auth.basicauth.users=admin:$$2y$$10$$YFPx3EmK6lN5bPG.zPNvp.UYQhkPvNnkZ7J4zYu2GODXJfHZXfYbK"  # admin:admin

          networks:
            traefik-net:
              name: traefik-net
              driver: bridge
        YAML

        compose_file = File.join(TRAEFIK_CONFIG_DIR, "docker-compose.yml")
        File.write(compose_file, compose_content)
        puts "✅ Docker Compose 파일이 생성되었습니다.".colorize(:green)
      end

      def create_traefik_config(email = nil)
        # 이메일 주소 확인
        email_file = File.join(TRAEFIK_CONFIG_DIR, ".email")
        email ||= File.exist?(email_file) ? File.read(email_file).strip : "admin@example.com"

        config_content = <<~YAML
          # Traefik 정적 설정
          api:
            dashboard: true
            debug: false

          entryPoints:
            web:
              address: ":80"
              http:
                redirections:
                  entryPoint:
                    to: websecure
                    scheme: https
                    permanent: true
            websecure:
              address: ":443"

          providers:
            docker:
              endpoint: "unix:///var/run/docker.sock"
              exposedByDefault: false
              network: traefik-net
              watch: true
            file:
              filename: /etc/traefik/dynamic.yml
              watch: true

          certificatesResolvers:
            myresolver:
              acme:
                email: #{email}
                storage: /acme.json
                tlsChallenge: {}
                # caServer: https://acme-staging-v02.api.letsencrypt.org/directory  # 테스트용

          log:
            level: INFO
            format: json

          accessLog:
            format: json
        YAML

        config_file = File.join(TRAEFIK_CONFIG_DIR, "config", "traefik.yml")
        File.write(config_file, config_content)
        puts "✅ Traefik 설정 파일이 생성되었습니다.".colorize(:green)
      end

      def create_dynamic_config(domains)
        routers = {}
        services = {}

        domains.each do |domain_info|
          domain = domain_info[:domain]
          safe_name = domain.gsub('.', '-').gsub('_', '-')

          # HTTP 라우터 (리다이렉트용)
          routers["#{safe_name}-http"] = {
            "rule" => "Host(`#{domain}`)",
            "entryPoints" => ["web"],
            "middlewares" => ["redirect-to-https"],
            "service" => "#{safe_name}-service"
          }

          # HTTPS 라우터
          routers["#{safe_name}-https"] = {
            "rule" => "Host(`#{domain}`)",
            "entryPoints" => ["websecure"],
            "service" => "#{safe_name}-service",
            "tls" => {
              "certResolver" => "myresolver"
            }
          }

          # 서비스 정의 (호스트의 3000 포트로)
          services["#{safe_name}-service"] = {
            "loadBalancer" => {
              "servers" => [
                { "url" => "http://host.docker.internal:3000" }
              ]
            }
          }
        end

        # 미들웨어 정의
        dynamic_config = {
          "http" => {
            "middlewares" => {
              "redirect-to-https" => {
                "redirectScheme" => {
                  "scheme" => "https",
                  "permanent" => true
                }
              }
            },
            "routers" => routers,
            "services" => services
          }
        }

        dynamic_file = File.join(TRAEFIK_CONFIG_DIR, "config", "dynamic.yml")
        File.write(dynamic_file, dynamic_config.to_yaml)
        puts "✅ 동적 라우팅 설정이 생성되었습니다.".colorize(:green)
      end

      def ensure_running
        if @docker.container_running?("traefik")
          puts "🔄 Traefik 컨테이너를 재시작합니다...".colorize(:yellow)
          reload_traefik
        else
          start_container
        end
      end

      def start_container
        puts "🚀 Traefik 컨테이너를 시작합니다...".colorize(:yellow)

        # 기존 컨테이너가 있다면 제거
        if @docker.container_exists?("traefik")
          @docker.stop_container("traefik")
        end

        # Docker Compose로 시작
        Dir.chdir(TRAEFIK_CONFIG_DIR) do
          if system("docker compose up -d")
            puts "✅ Traefik이 시작되었습니다.".colorize(:green)

            # 시작 완료 대기
            sleep 3

            # 상태 확인
            check_traefik_status
          else
            puts "❌ Traefik 시작에 실패했습니다.".colorize(:red)
            exit 1
          end
        end
      end

      def reload_traefik
        puts "🔄 Traefik 설정을 다시 로드합니다...".colorize(:yellow)

        Dir.chdir(TRAEFIK_CONFIG_DIR) do
          if system("docker compose restart")
            puts "✅ Traefik이 재시작되었습니다.".colorize(:green)
          else
            puts "⚠️  Traefik 재시작에 실패했습니다.".colorize(:yellow)
          end
        end
      end

      def check_traefik_status
        # 대시보드 접근 확인
        puts "\n📊 Traefik 대시보드: http://localhost:8080".colorize(:cyan)
        puts "   (기본 인증: admin / admin)".colorize(:gray)

        # 로그 확인
        logs = `docker logs traefik --tail 5 2>&1`.strip
        if logs.include?("error") || logs.include?("Error")
          puts "\n⚠️  Traefik 로그에 오류가 발견되었습니다:".colorize(:yellow)
          puts logs.colorize(:gray)
        end
      end

      def configure_routes(domains)
        puts "\n📝 도메인 라우팅 상태:".colorize(:yellow)

        domains.each do |domain_info|
          domain = domain_info[:domain]
          puts "   • #{domain} → localhost:3000".colorize(:green)
          puts "     HTTP:  http://#{domain} (→ HTTPS 리다이렉트)".colorize(:gray)
          puts "     HTTPS: https://#{domain} (Let's Encrypt 인증서)".colorize(:gray)
        end

        puts "\n💡 Let's Encrypt 인증서 발급 중...".colorize(:yellow)
        puts "   첫 발급에는 1-2분이 소요될 수 있습니다.".colorize(:gray)
      end
    end
  end
end