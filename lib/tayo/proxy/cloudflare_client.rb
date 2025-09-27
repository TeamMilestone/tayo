# frozen_string_literal: true

require "colorize"
require "tty-prompt"
require "net/http"
require "json"
require "uri"
require "fileutils"

module Tayo
  module Proxy
    class CloudflareClient
      TOKEN_FILE = File.expand_path("~/.tayo/cloudflare_token")

      def initialize
        @prompt = TTY::Prompt.new
      end

      def ensure_token
        @token = load_saved_token

        if @token
          puts "🔑 저장된 Cloudflare 토큰을 확인합니다...".colorize(:yellow)

          if test_token(@token)
            puts "✅ 저장된 Cloudflare 토큰이 유효합니다.".colorize(:green)
          else
            puts "⚠️  저장된 토큰이 만료되었거나 유효하지 않습니다.".colorize(:yellow)
            puts "새 토큰을 입력해주세요.".colorize(:cyan)
            open_token_creation_page
            @token = get_cloudflare_token
            save_token(@token)
          end
        else
          puts "\n🔑 Cloudflare API 토큰이 필요합니다.".colorize(:yellow)
          open_token_creation_page
          @token = get_cloudflare_token
          save_token(@token)
        end
      end

      def select_domains
        puts "\n🌐 Cloudflare 도메인 목록을 조회합니다...".colorize(:yellow)

        zones = get_cloudflare_zones

        if zones.empty?
          puts "❌ Cloudflare에 등록된 도메인이 없습니다.".colorize(:red)
          puts "먼저 https://dash.cloudflare.com 에서 도메인을 추가해주세요.".colorize(:cyan)
          return []
        end

        zone_choices = zones.map { |zone| "#{zone['name']} (#{zone['status']})" }

        selected_zones = @prompt.multi_select(
          "Caddy로 라우팅할 도메인을 선택하세요 (Space로 선택, Enter로 완료):",
          zone_choices,
          per_page: 10,
          min: 1
        )

        # 선택된 항목이 없으면 빈 배열 반환
        return [] if selected_zones.nil? || selected_zones.empty?

        puts "DEBUG: selected_zones = #{selected_zones.inspect}" if ENV["DEBUG"]

        selected_domains = selected_zones.map do |selection|
          zone_name = selection.split(' ').first
          zone = zones.find { |z| z['name'] == zone_name }

          # 서브도메인 추가 여부 확인
          if @prompt.yes?("#{zone_name}에 서브도메인을 추가하시겠습니까?")
            subdomain = @prompt.ask("서브도메인을 입력하세요 (예: app, api):")
            if subdomain && !subdomain.empty?
              {
                domain: "#{subdomain}.#{zone_name}",
                zone_id: zone['id'],
                zone_name: zone_name
              }
            else
              {
                domain: zone_name,
                zone_id: zone['id'],
                zone_name: zone_name
              }
            end
          else
            {
              domain: zone_name,
              zone_id: zone['id'],
              zone_name: zone_name
            }
          end
        end

        puts "\n✅ 선택된 도메인:".colorize(:green)
        selected_domains.each do |d|
          puts "   • #{d[:domain]}".colorize(:cyan)
        end

        puts "DEBUG: returning selected_domains = #{selected_domains.inspect}" if ENV["DEBUG"]

        selected_domains
      end

      def setup_dns_records(domains, public_ip)
        domains.each do |domain_info|
          domain = domain_info[:domain]
          zone_id = domain_info[:zone_id]

          puts "\n⚙️  #{domain}의 DNS 레코드를 설정합니다...".colorize(:yellow)

          # 기존 A 레코드 확인
          existing_records = get_dns_records(zone_id, domain, ['A'])

          if existing_records.any?
            existing_record = existing_records.first
            if existing_record['content'] == public_ip
              puts "✅ #{domain} → #{public_ip} (이미 설정됨)".colorize(:green)
            else
              puts "⚠️  기존 레코드를 업데이트합니다.".colorize(:yellow)
              update_dns_record(zone_id, existing_record['id'], public_ip)
            end
          else
            # 새 A 레코드 생성
            create_dns_record(zone_id, domain, 'A', public_ip)
          end
        end
      end

      private

      def load_saved_token
        return nil unless File.exist?(TOKEN_FILE)
        File.read(TOKEN_FILE).strip
      rescue
        nil
      end

      def save_token(token)
        dir = File.dirname(TOKEN_FILE)

        # 디렉토리가 파일로 존재하는 경우 삭제
        if File.exist?(dir) && !File.directory?(dir)
          FileUtils.rm(dir)
        end

        # 디렉토리가 없을 때만 생성
        FileUtils.mkdir_p(dir) unless File.directory?(dir)

        File.write(TOKEN_FILE, token)
        File.chmod(0600, TOKEN_FILE)
        puts "✅ API 토큰이 저장되었습니다.".colorize(:green)
      end

      def open_token_creation_page
        puts "토큰 생성 페이지를 엽니다...".colorize(:cyan)
        system("open 'https://dash.cloudflare.com/profile/api-tokens' 2>/dev/null || xdg-open 'https://dash.cloudflare.com/profile/api-tokens' 2>/dev/null")

        puts "\n다음 권한으로 토큰을 생성해주세요:".colorize(:yellow)
        puts ""
        puts "한국어 화면:".colorize(:gray)
        puts "• 영역 → 영역 → 읽기".colorize(:white)
        puts "• 영역 → DNS → 편집".colorize(:white)
        puts "  (영역 리소스는 '모든 영역' 선택)".colorize(:gray)
        puts ""
        puts "English:".colorize(:gray)
        puts "• Zone → Zone → Read".colorize(:white)
        puts "• Zone → DNS → Edit".colorize(:white)
        puts "  (Zone Resources: Select 'All zones')".colorize(:gray)
        puts ""
      end

      def get_cloudflare_token
        token = @prompt.mask("생성된 Cloudflare API 토큰을 붙여넣으세요:")

        if token.nil? || token.strip.empty?
          puts "❌ 토큰이 입력되지 않았습니다.".colorize(:red)
          exit 1
        end

        if test_token(token.strip)
          puts "✅ 토큰이 확인되었습니다.".colorize(:green)
          return token.strip
        else
          puts "❌ 토큰이 올바르지 않거나 권한이 부족합니다.".colorize(:red)
          exit 1
        end
      end

      def test_token(token)
        uri = URI('https://api.cloudflare.com/client/v4/user/tokens/verify')
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{token}"
        request['Content-Type'] = 'application/json'

        response = http.request(request)

        if response.code == '200'
          data = JSON.parse(response.body)
          return data['success'] == true
        else
          return false
        end
      rescue => e
        puts "⚠️  토큰 검증 중 오류: #{e.message}".colorize(:yellow) if ENV["DEBUG"]
        false
      end

      def get_cloudflare_zones
        uri = URI('https://api.cloudflare.com/client/v4/zones')
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{@token}"
        request['Content-Type'] = 'application/json'

        response = http.request(request)

        if response.code == '200'
          data = JSON.parse(response.body)
          return data['result'] || []
        else
          puts "❌ 도메인 목록 조회에 실패했습니다: #{response.code}".colorize(:red)
          []
        end
      rescue => e
        puts "❌ API 요청 중 오류가 발생했습니다: #{e.message}".colorize(:red)
        []
      end

      def get_dns_records(zone_id, name, types)
        records = []

        types.each do |type|
          uri = URI("https://api.cloudflare.com/client/v4/zones/#{zone_id}/dns_records")
          uri.query = URI.encode_www_form({
            type: type,
            name: name
          })

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true

          request = Net::HTTP::Get.new(uri)
          request['Authorization'] = "Bearer #{@token}"
          request['Content-Type'] = 'application/json'

          response = http.request(request)

          if response.code == '200'
            data = JSON.parse(response.body)
            records.concat(data['result'] || [])
          end
        end

        records
      rescue => e
        puts "⚠️  DNS 레코드 조회 중 오류: #{e.message}".colorize(:yellow)
        []
      end

      def create_dns_record(zone_id, name, type, content)
        uri = URI("https://api.cloudflare.com/client/v4/zones/#{zone_id}/dns_records")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Bearer #{@token}"
        request['Content-Type'] = 'application/json'

        data = {
          type: type,
          name: name,
          content: content,
          ttl: 300,
          proxied: false
        }

        request.body = data.to_json
        response = http.request(request)

        if response.code == '200'
          puts "✅ #{name} → #{content} (A 레코드 생성됨)".colorize(:green)
        else
          puts "❌ DNS 레코드 생성 실패: #{response.code}".colorize(:red)
          puts response.body if ENV["DEBUG"]
        end
      rescue => e
        puts "❌ DNS 레코드 생성 중 오류: #{e.message}".colorize(:red)
      end

      def update_dns_record(zone_id, record_id, new_content)
        uri = URI("https://api.cloudflare.com/client/v4/zones/#{zone_id}/dns_records/#{record_id}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Patch.new(uri)
        request['Authorization'] = "Bearer #{@token}"
        request['Content-Type'] = 'application/json'

        data = {
          content: new_content
        }

        request.body = data.to_json
        response = http.request(request)

        if response.code == '200'
          puts "✅ DNS 레코드가 업데이트되었습니다.".colorize(:green)
        else
          puts "❌ DNS 레코드 업데이트 실패: #{response.code}".colorize(:red)
        end
      rescue => e
        puts "❌ DNS 레코드 업데이트 중 오류: #{e.message}".colorize(:red)
      end
    end
  end
end