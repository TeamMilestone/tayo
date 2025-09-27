# frozen_string_literal: true

require "colorize"
require "tty-prompt"

module Tayo
  module Proxy
    class NetworkConfig
      attr_reader :public_ip, :internal_ip, :external_http, :external_https

      def initialize
        @prompt = TTY::Prompt.new
        @use_custom_ports = false
      end

      def detect_ips
        puts "\n🔍 네트워크 정보를 확인합니다...".colorize(:yellow)

        # 공인 IP 감지
        print "공인 IP 확인 중... "
        @public_ip = detect_public_ip
        puts "#{@public_ip}".colorize(:green)

        # 내부 IP 감지
        print "내부 IP 확인 중... "
        @internal_ip = detect_internal_ip
        puts "#{@internal_ip}".colorize(:green)

        puts ""
      end

      def configure_ports
        puts "\n🌐 외부 접속 포트를 설정합니다.".colorize(:yellow)
        puts "Kamal Proxy는 항상 80, 443 포트를 사용합니다.".colorize(:gray)
        puts ""

        choices = [
          { name: "공유기에서 80, 443을 직접 포워딩 (기본)", value: :direct },
          { name: "다른 포트를 사용하여 포워딩 (예: 8080→80, 8443→443)", value: :custom }
        ]

        choice = @prompt.select("포트 설정 방식을 선택하세요:", choices)

        if choice == :custom
          @use_custom_ports = true

          @external_http = @prompt.ask("HTTP 외부 포트 (기본: 8080):", default: "8080")
          @external_https = @prompt.ask("HTTPS 외부 포트 (기본: 8443):", default: "8443")

          puts "\n✅ 외부 포트가 설정되었습니다:".colorize(:green)
          puts "   HTTP:  #{@external_http}".colorize(:gray)
          puts "   HTTPS: #{@external_https}".colorize(:gray)
        else
          @external_http = "80"
          @external_https = "443"

          puts "\n✅ 표준 포트(80, 443)를 사용합니다.".colorize(:green)
        end
      end

      def use_custom_ports?
        @use_custom_ports
      end

      def show_port_forwarding_guide
        return unless use_custom_ports?

        puts "\n📡 공유기 포트포워딩 설정 안내:".colorize(:yellow)
        puts "━" * 50
        puts "외부 포트 #{@external_http} → #{@internal_ip}:80".colorize(:white)
        puts "외부 포트 #{@external_https} → #{@internal_ip}:443".colorize(:white)
        puts "━" * 50
        puts ""
        puts "위 설정을 공유기 관리 페이지에서 완료해주세요.".colorize(:cyan)
        puts "일반적인 접속 주소: http://192.168.1.1".colorize(:gray)
      end

      private

      def detect_public_ip
        # curl을 사용한 공인 IP 감지
        ip = `curl -s ifconfig.me 2>/dev/null`.strip

        # 대체 방법들
        if ip.empty? || !valid_ip?(ip)
          ip = `curl -s ipecho.net/plain 2>/dev/null`.strip
        end

        if ip.empty? || !valid_ip?(ip)
          ip = `curl -s icanhazip.com 2>/dev/null`.strip
        end

        if ip.empty? || !valid_ip?(ip)
          puts "\n⚠️  공인 IP를 자동으로 감지할 수 없습니다.".colorize(:yellow)
          ip = @prompt.ask("공인 IP를 직접 입력해주세요:") do |q|
            q.validate(/\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/, "올바른 IP 형식을 입력해주세요")
          end
        end

        ip
      end

      def detect_internal_ip
        # macOS
        if RUBY_PLATFORM.include?("darwin")
          # en0 (Wi-Fi) 또는 en1 (Ethernet) 인터페이스에서 IP 추출
          ip = `ifconfig en0 2>/dev/null | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}'`.strip
          ip = `ifconfig en1 2>/dev/null | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}'`.strip if ip.empty?

          # 다른 인터페이스 검색
          if ip.empty?
            ip = `ifconfig | grep 'inet ' | grep -v 127.0.0.1 | grep -v '::1' | head -1 | awk '{print $2}'`.strip
          end
        else
          # Linux
          ip = `hostname -I 2>/dev/null | awk '{print $1}'`.strip

          if ip.empty?
            ip = `ip addr show | grep 'inet ' | grep -v 127.0.0.1 | grep -v '::1' | head -1 | awk '{print $2}' | cut -d/ -f1`.strip
          end
        end

        # 여전히 비어있다면 수동 입력
        if ip.empty? || !valid_ip?(ip)
          puts "\n⚠️  내부 IP를 자동으로 감지할 수 없습니다.".colorize(:yellow)
          ip = @prompt.ask("내부 IP를 직접 입력해주세요 (예: 192.168.1.100):") do |q|
            q.validate(/\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/, "올바른 IP 형식을 입력해주세요")
          end
        end

        ip
      end

      def valid_ip?(ip)
        return false if ip.nil? || ip.empty?

        parts = ip.split('.')
        return false unless parts.length == 4

        parts.all? do |part|
          num = part.to_i
          num >= 0 && num <= 255 && part == num.to_s
        end
      end
    end
  end
end