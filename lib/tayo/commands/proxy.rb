# frozen_string_literal: true

require "colorize"
require "tty-prompt"
require_relative "../proxy/cloudflare_client"
require_relative "../proxy/docker_manager"
require_relative "../proxy/network_config"
require_relative "../proxy/traefik_config"
require_relative "../proxy/welcome_service"

module Tayo
  module Commands
    class Proxy
      def execute
        puts "🚀 Kamal Proxy와 Caddy 설정을 시작합니다...".colorize(:green)
        puts ""

        # 1. Cloudflare 설정
        cloudflare = Tayo::Proxy::CloudflareClient.new
        cloudflare.ensure_token

        # 2. 네트워크 설정
        network = Tayo::Proxy::NetworkConfig.new
        network.detect_ips
        network.configure_ports

        # 3. Docker 확인
        docker = Tayo::Proxy::DockerManager.new
        docker.check_containers

        # 4. 도메인 선택
        selected_domains = cloudflare.select_domains

        if selected_domains.empty?
          puts "❌ 도메인이 선택되지 않았습니다. 종료합니다.".colorize(:red)
          return
        end

        # 5. DNS 설정
        puts "\n📝 DNS 레코드를 설정합니다...".colorize(:yellow)
        cloudflare.setup_dns_records(selected_domains, network.public_ip)

        # 6. Welcome 서비스 확인
        welcome = Tayo::Proxy::WelcomeService.new
        welcome.ensure_running

        # 7. Traefik 설정
        traefik = Tayo::Proxy::TraefikConfig.new
        traefik.setup(selected_domains)

        # 8. 최종 안내
        show_summary(selected_domains, network)

      rescue => e
        puts "❌ 오류가 발생했습니다: #{e.message}".colorize(:red)
        puts e.backtrace.join("\n") if ENV["DEBUG"]
        exit 1
      end

      private

      def show_summary(domains, network)
        puts "\n" + "="*60
        puts "✅ Proxy 설정이 완료되었습니다!".colorize(:green)
        puts "="*60

        puts "\n📋 설정 요약:".colorize(:yellow)
        puts "━"*40
        puts "공인 IP: #{network.public_ip}".colorize(:white)
        puts "내부 IP: #{network.internal_ip}".colorize(:white)
        puts "Traefik: 80, 443 포트 사용 중".colorize(:white)
        puts "대시보드: http://localhost:8080".colorize(:white)
        puts "━"*40

        puts "\n🌐 활성화된 도메인:".colorize(:yellow)
        domains.each do |domain|
          if network.use_custom_ports?
            puts "• #{domain}".colorize(:cyan)
            puts "  HTTP:  http://#{domain}:#{network.external_http}".colorize(:gray)
            puts "  HTTPS: https://#{domain}:#{network.external_https}".colorize(:gray)
          else
            puts "• #{domain}".colorize(:cyan)
            puts "  HTTP:  http://#{domain}".colorize(:gray)
            puts "  HTTPS: https://#{domain}".colorize(:gray)
          end
        end

        if network.use_custom_ports?
          puts "\n💡 공유기 포트포워딩을 설정하세요!".colorize(:yellow)
          network.show_port_forwarding_guide
        end

        puts "\n🎉 모든 설정이 완료되었습니다!".colorize(:green)
      end
    end
  end
end