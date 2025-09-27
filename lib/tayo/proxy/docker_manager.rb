# frozen_string_literal: true

require "colorize"
require "json"

module Tayo
  module Proxy
    class DockerManager
      def check_containers
        puts "\n🐳 Docker 컨테이너 상태를 확인합니다...".colorize(:yellow)

        unless docker_installed?
          puts "❌ Docker가 설치되어 있지 않습니다.".colorize(:red)
          puts "https://www.docker.com/get-started 에서 Docker를 설치해주세요.".colorize(:cyan)
          exit 1
        end

        unless docker_running?
          puts "❌ Docker가 실행되고 있지 않습니다.".colorize(:red)
          puts "Docker Desktop을 실행해주세요.".colorize(:cyan)
          exit 1
        end

        # Kamal Proxy 상태 확인
        check_kamal_proxy_status

        # Caddy 상태 확인
        check_caddy_status

        puts ""
      end

      def container_exists?(name)
        output = `docker ps -a --filter "name=^#{name}$" --format "{{.Names}}" 2>/dev/null`.strip
        !output.empty?
      end

      def container_running?(name)
        output = `docker ps --filter "name=^#{name}$" --format "{{.Names}}" 2>/dev/null`.strip
        !output.empty?
      end

      def check_port_binding(container, ports)
        return false unless container_running?(container)

        ports.all? do |port|
          output = `docker port #{container} #{port} 2>/dev/null`.strip
          !output.empty?
        end
      end

      def port_in_use?(port)
        # Docker 컨테이너가 포트를 사용 중인지 확인
        docker_using = `docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -E "0\\.0\\.0\\.0:#{port}->|\\*:#{port}->" 2>/dev/null`.strip
        return true unless docker_using.empty?

        # 시스템 포트 확인
        if RUBY_PLATFORM.include?("darwin")
          # macOS
          output = `lsof -iTCP:#{port} -sTCP:LISTEN 2>/dev/null`.strip
        else
          # Linux
          output = `netstat -tln 2>/dev/null | grep ":#{port}"`.strip
          output = `ss -tln 2>/dev/null | grep ":#{port}"`.strip if output.empty?
        end

        !output.empty?
      end

      def stop_container(name)
        return unless container_exists?(name)

        puts "🛑 #{name} 컨테이너를 중지합니다...".colorize(:yellow)
        system("docker stop #{name} >/dev/null 2>&1")
        system("docker rm #{name} >/dev/null 2>&1")
      end

      def get_container_network(name)
        return nil unless container_running?(name)

        output = `docker inspect #{name} --format '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' 2>/dev/null`.strip
        output.empty? ? nil : output
      end

      def create_network_if_not_exists(network_name = "tayo-proxy")
        existing = `docker network ls --filter "name=^#{network_name}$" --format "{{.Name}}" 2>/dev/null`.strip

        if existing.empty?
          puts "📡 Docker 네트워크 '#{network_name}'를 생성합니다...".colorize(:yellow)
          system("docker network create #{network_name} >/dev/null 2>&1")
        end

        network_name
      end

      private

      def docker_installed?
        system("which docker >/dev/null 2>&1")
      end

      def docker_running?
        system("docker info >/dev/null 2>&1")
      end

      def check_kamal_proxy_status
        # Traefik으로 교체되어 더 이상 사용하지 않음
        check_traefik_status
      end

      def check_traefik_status
        if container_running?("traefik")
          if check_port_binding("traefik", [80, 443])
            puts "✅ Traefik: 실행 중 (80, 443 포트 사용)".colorize(:green)
          else
            puts "⚠️  Traefik: 실행 중이지만 포트가 올바르게 바인딩되지 않음".colorize(:yellow)
            show_port_conflicts
          end
        elsif container_exists?("traefik")
          puts "⚠️  Traefik: 중지됨".colorize(:yellow)
        else
          puts "ℹ️  Traefik: 설치되지 않음".colorize(:gray)
        end
      end

      def check_caddy_status
        # Caddy는 더 이상 사용하지 않음
        # 이 메서드는 하위 호환성을 위해 유지하지만 아무것도 하지 않음
      end

      def show_port_conflicts
        [80, 443].each do |port|
          if port_in_use?(port)
            # 포트를 사용 중인 프로세스 찾기
            if RUBY_PLATFORM.include?("darwin")
              process = `lsof -iTCP:#{port} -sTCP:LISTEN 2>/dev/null | grep LISTEN | head -1`.strip
            else
              process = `netstat -tlnp 2>/dev/null | grep ":#{port}" | head -1`.strip
            end

            unless process.empty?
              puts "   ⚠️  포트 #{port}가 다른 프로세스에서 사용 중입니다:".colorize(:yellow)
              puts "      #{process}".colorize(:gray)
            end
          end
        end
      end
    end
  end
end