# frozen_string_literal: true

require "colorize"
require "tty-prompt"
require "net/http"
require "json"
require "uri"
require "fileutils"
require "yaml"

module Tayo
  module Commands
    class Cf
      CLOUDFLARE_TOKEN_FILE = File.expand_path("~/.config/tayo/cloudflare_token")
      SERVER_CONFIG_FILE = File.expand_path("~/.config/tayo/server.yml")

      def execute
        puts "☁️  Cloudflare DNS 설정을 시작합니다...".colorize(:green)

        # 1. Cloudflare 인증 확인 (저장된 토큰 확인 또는 새로 입력)
        token = check_cloudflare_auth

        # 2. Cloudflare API로 도메인 목록 조회 및 선택
        selected_zone = select_cloudflare_zone(token)

        # 4. 기존 레코드 목록 표시
        show_existing_records(token, selected_zone)

        # 5. 서비스 도메인 입력받기
        domain_info = get_domain_input(selected_zone)

        # 6. 홈서버 연결 정보 입력받기
        server_info = get_server_info

        # 7. DNS 레코드 추가/수정
        setup_dns_record(token, selected_zone, domain_info, server_info)

        # 8. config/deploy.yml 업데이트
        update_deploy_config(domain_info, server_info)

        puts "\n🎉 Cloudflare DNS 설정이 완료되었습니다!".colorize(:green)

        # 변경사항 커밋
        commit_cloudflare_changes(domain_info)
      end

      private

      def get_domain_input(zone)
        prompt = TTY::Prompt.new
        zone_name = zone['name']

        puts "📝 서비스 도메인을 설정합니다.".colorize(:yellow)
        puts "   선택된 Zone: #{zone_name}".colorize(:gray)

        use_subdomain = prompt.yes?("서브도메인을 사용하시겠습니까? (예: app.#{zone_name})")

        if use_subdomain
          subdomain = prompt.ask("서브도메인을 입력하세요 (예: app, api, www):") do |q|
            q.validate(/\A[a-zA-Z0-9-]+\z/, "올바른 서브도메인을 입력해주세요 (영문, 숫자, 하이픈만 가능)")
          end
          full_domain = "#{subdomain}.#{zone_name}"
          { type: :subdomain, domain: full_domain, zone: zone_name, subdomain: subdomain }
        else
          { type: :root, domain: zone_name, zone: zone_name }
        end
      end

      def get_server_info
        prompt = TTY::Prompt.new

        puts "\n🖥️  홈서버 연결 정보를 확인합니다.".colorize(:yellow)

        # 저장된 서버 정보 확인
        saved_config = load_server_config

        if saved_config
          puts "\n저장된 홈서버 정보:".colorize(:cyan)
          puts "   • 서버: #{saved_config['server_address']}".colorize(:white)
          puts "   • SSH 사용자: #{saved_config['ssh_user']}".colorize(:white)

          if prompt.yes?("\n이 정보를 사용하시겠습니까?")
            server_address = saved_config['server_address']
            ssh_user = saved_config['ssh_user']
          else
            server_address, ssh_user = prompt_server_info(prompt)
            save_server_config(server_address, ssh_user)
          end
        else
          server_address, ssh_user = prompt_server_info(prompt)
          save_server_config(server_address, ssh_user)
        end

        # IP인지 도메인인지 판단
        is_ip = server_address.match?(/\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/)
        record_type = is_ip ? 'A' : 'CNAME'

        {
          address: server_address,
          ssh_user: ssh_user,
          record_type: record_type
        }
      end

      def prompt_server_info(prompt)
        server_address = prompt.ask("홈서버 IP 또는 도메인을 입력하세요:") do |q|
          q.validate(/\A.+\z/, "서버 정보를 입력해주세요")
        end

        ssh_user = prompt.ask("SSH 사용자 계정을 입력하세요:", default: "root")

        [server_address, ssh_user]
      end

      def load_server_config
        return nil unless File.exist?(SERVER_CONFIG_FILE)

        config = YAML.load_file(SERVER_CONFIG_FILE)
        return nil unless config.is_a?(Hash)
        return nil unless config['server_address'] && config['ssh_user']

        config
      rescue
        nil
      end

      def save_server_config(server_address, ssh_user)
        dir = File.dirname(SERVER_CONFIG_FILE)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

        config = {
          'server_address' => server_address,
          'ssh_user' => ssh_user
        }

        File.write(SERVER_CONFIG_FILE, config.to_yaml)
        File.chmod(0600, SERVER_CONFIG_FILE)

        puts "✅ 홈서버 정보가 저장되었습니다.".colorize(:green)
      end

      def check_cloudflare_auth
        # 1. 환경변수에서 토큰 확인
        token = ENV['CLOUDFLARE_API_TOKEN']
        if token && !token.strip.empty?
          if test_cloudflare_token(token.strip)
            puts "✅ Cloudflare에 로그인되어 있습니다. (환경변수)".colorize(:green)
            return token.strip
          else
            puts "⚠️  환경변수의 Cloudflare 토큰이 유효하지 않습니다.".colorize(:yellow)
          end
        end

        # 2. 저장된 파일에서 토큰 확인
        if File.exist?(CLOUDFLARE_TOKEN_FILE)
          token = File.read(CLOUDFLARE_TOKEN_FILE).strip
          if !token.empty? && test_cloudflare_token(token)
            puts "✅ Cloudflare에 로그인되어 있습니다.".colorize(:green)
            return token
          else
            puts "⚠️  저장된 Cloudflare 토큰이 유효하지 않습니다.".colorize(:yellow)
          end
        end

        # 3. 새 토큰 요청
        request_new_cloudflare_token
      end

      def request_new_cloudflare_token
        prompt = TTY::Prompt.new

        puts "\n🔑 Cloudflare API 토큰이 필요합니다.".colorize(:yellow)
        puts "토큰 생성 페이지를 엽니다...".colorize(:cyan)

        # Cloudflare API 토큰 생성 페이지 열기
        system("open 'https://dash.cloudflare.com/profile/api-tokens'")

        puts "\n다음 권한으로 토큰을 생성해주세요:".colorize(:yellow)
        puts ""
        puts "한국어 화면:".colorize(:gray)
        puts "• 영역 → DNS → 편집".colorize(:white)
        puts "  (영역 리소스는 '모든 영역' 선택)".colorize(:gray)
        puts ""
        puts "English:".colorize(:gray)
        puts "• Zone → DNS → Edit".colorize(:white)
        puts "  (Zone Resources: Select 'All zones')".colorize(:gray)
        puts ""

        token = prompt.mask("생성된 Cloudflare API 토큰을 붙여넣으세요:")

        if token.nil? || token.strip.empty?
          puts "❌ 토큰이 입력되지 않았습니다.".colorize(:red)
          exit 1
        end

        token = token.strip

        # 토큰 유효성 확인
        if test_cloudflare_token(token)
          save_cloudflare_token(token)
          puts "✅ 토큰이 확인되고 저장되었습니다.".colorize(:green)
          return token
        else
          puts "❌ 토큰이 올바르지 않거나 권한이 부족합니다.".colorize(:red)
          exit 1
        end
      end

      def save_cloudflare_token(token)
        # 디렉토리 생성
        dir = File.dirname(CLOUDFLARE_TOKEN_FILE)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

        # 토큰 저장 (파일 권한 600으로 설정)
        File.write(CLOUDFLARE_TOKEN_FILE, token)
        File.chmod(0600, CLOUDFLARE_TOKEN_FILE)
      end

      def test_cloudflare_token(token)
        uri = URI('https://api.cloudflare.com/client/v4/user/tokens/verify')
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        
        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{token}"
        request['Content-Type'] = 'application/json'
        
        response = http.request(request)
        return response.code == '200'
      rescue
        return false
      end

      def select_cloudflare_zone(token)
        puts "\n🌐 Cloudflare 도메인 목록을 조회합니다...".colorize(:yellow)
        
        zones = get_cloudflare_zones(token)
        
        if zones.empty?
          puts "❌ Cloudflare에 등록된 도메인이 없습니다.".colorize(:red)
          puts "먼저 https://dash.cloudflare.com 에서 도메인을 추가해주세요.".colorize(:cyan)
          exit 1
        end
        
        prompt = TTY::Prompt.new
        zone_choices = zones.map { |zone| "#{zone['name']} (#{zone['status']})" }
        
        selected = prompt.select("도메인을 선택하세요:", zone_choices)
        zone_name = selected.split(' ').first
        
        selected_zone = zones.find { |zone| zone['name'] == zone_name }
        puts "✅ 선택된 도메인: #{zone_name}".colorize(:green)
        
        return selected_zone
      end

      def get_cloudflare_zones(token)
        uri = URI('https://api.cloudflare.com/client/v4/zones')
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        
        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{token}"
        request['Content-Type'] = 'application/json'
        
        response = http.request(request)
        
        if response.code == '200'
          data = JSON.parse(response.body)
          return data['result'] || []
        else
          puts "❌ 도메인 목록 조회에 실패했습니다: #{response.code}".colorize(:red)
          exit 1
        end
      rescue => e
        puts "❌ API 요청 중 오류가 발생했습니다: #{e.message}".colorize(:red)
        exit 1
      end

      def show_existing_records(token, zone)
        puts "\n🔍 기존 DNS 레코드를 확인합니다...".colorize(:yellow)

        zone_id = zone['id']
        zone_name = zone['name']

        # Zone의 모든 A/CNAME 레코드 조회
        records = get_all_dns_records(token, zone_id, ['A', 'CNAME'])

        if records.empty?
          puts "   등록된 A/CNAME 레코드가 없습니다.".colorize(:gray)
        else
          puts "   #{zone_name}의 기존 레코드:".colorize(:cyan)
          records.each do |record|
            puts "   • #{record['name']} → #{record['content']} (#{record['type']})".colorize(:white)
          end
        end

        puts ""
      end

      def get_all_dns_records(token, zone_id, types)
        records = []

        types.each do |type|
          uri = URI("https://api.cloudflare.com/client/v4/zones/#{zone_id}/dns_records")
          uri.query = URI.encode_www_form({ type: type })

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true

          request = Net::HTTP::Get.new(uri)
          request['Authorization'] = "Bearer #{token}"
          request['Content-Type'] = 'application/json'

          response = http.request(request)

          if response.code == '200'
            data = JSON.parse(response.body)
            records.concat(data['result'] || [])
          end
        end

        records.sort_by { |r| r['name'] }
      rescue => e
        puts "⚠️  DNS 레코드 조회 중 오류: #{e.message}".colorize(:yellow)
        []
      end

      def get_dns_records(token, zone_id, name, types)
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
          request['Authorization'] = "Bearer #{token}"
          request['Content-Type'] = 'application/json'
          
          response = http.request(request)
          
          if response.code == '200'
            data = JSON.parse(response.body)
            records.concat(data['result'] || [])
          end
        end
        
        return records
      rescue => e
        puts "❌ DNS 레코드 조회 중 오류: #{e.message}".colorize(:red)
        return []
      end

      def setup_dns_record(token, zone, domain_info, server_info)
        puts "\n⚙️  DNS 레코드를 설정합니다...".colorize(:yellow)

        zone_id = zone['id']
        target_domain = domain_info[:domain]
        server_address = server_info[:address]
        record_type = server_info[:record_type]

        # 대상 도메인의 기존 A/CNAME 레코드 확인
        existing_records = get_dns_records(token, zone_id, target_domain, ['A', 'CNAME'])

        if existing_records.any?
          existing_record = existing_records.first

          # 동일한 타입이고 같은 값이면 건너뛰기
          if existing_record['type'] == record_type && existing_record['content'] == server_address
            puts "✅ DNS 레코드가 이미 올바르게 설정되어 있습니다.".colorize(:green)
            puts "   #{target_domain} → #{server_address} (#{record_type} 레코드)".colorize(:gray)
          else
            # 타입이 다르거나 값이 다른 경우 삭제 후 재생성
            puts "⚠️  기존 레코드를 삭제하고 새로 생성합니다.".colorize(:yellow)
            puts "   기존: #{existing_record['content']} (#{existing_record['type']}) → 새로운: #{server_address} (#{record_type})".colorize(:gray)

            # 기존 레코드 삭제
            delete_dns_record(token, zone_id, existing_record['id'])

            # 새 레코드 생성
            create_dns_record(token, zone_id, target_domain, record_type, server_address)
          end
        else
          # DNS 레코드 생성
          create_dns_record(token, zone_id, target_domain, record_type, server_address)
        end

        puts "   #{target_domain} → #{server_address}".colorize(:cyan)
      end

      def create_dns_record(token, zone_id, name, type, content)
        uri = URI("https://api.cloudflare.com/client/v4/zones/#{zone_id}/dns_records")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        
        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Bearer #{token}"
        request['Content-Type'] = 'application/json'
        
        data = {
          type: type,
          name: name,
          content: content,
          ttl: 300
        }
        
        request.body = data.to_json
        response = http.request(request)
        
        if response.code == '200'
          puts "✅ DNS 레코드가 생성되었습니다.".colorize(:green)
          puts "   #{name} → #{content} (#{type} 레코드)".colorize(:gray)
        else
          puts "❌ DNS 레코드 생성에 실패했습니다: #{response.code}".colorize(:red)
          puts response.body
          exit 1
        end
      rescue => e
        puts "❌ DNS 레코드 생성 중 오류: #{e.message}".colorize(:red)
        exit 1
      end

      def delete_dns_record(token, zone_id, record_id)
        uri = URI("https://api.cloudflare.com/client/v4/zones/#{zone_id}/dns_records/#{record_id}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        
        request = Net::HTTP::Delete.new(uri)
        request['Authorization'] = "Bearer #{token}"
        request['Content-Type'] = 'application/json'
        
        response = http.request(request)
        
        if response.code == '200'
          puts "✅ 기존 DNS 레코드가 삭제되었습니다.".colorize(:green)
        else
          puts "❌ DNS 레코드 삭제에 실패했습니다: #{response.code}".colorize(:red)
          puts response.body
          exit 1
        end
      rescue => e
        puts "❌ DNS 레코드 삭제 중 오류: #{e.message}".colorize(:red)
        exit 1
      end

      def update_deploy_config(domain_info, server_info)
        puts "\n📝 배포 설정을 업데이트합니다...".colorize(:yellow)

        config_file = "config/deploy.yml"
        final_domain = domain_info[:domain]
        server_address = server_info[:address]
        ssh_user = server_info[:ssh_user]

        unless File.exist?(config_file)
          puts "⚠️  config/deploy.yml 파일이 없습니다.".colorize(:yellow)
          return
        end

        content = File.read(config_file)

        # proxy 섹션 설정
        # 1. 활성화된 proxy 섹션이 있는지 확인 (줄 시작이 'proxy:'인 경우)
        # 2. 주석 처리된 proxy 섹션이 있으면 활성화
        # 3. 없으면 새로 추가
        if content.match?(/^proxy:\s*$/m)
          # 활성화된 proxy 섹션이 있음 - host 값만 업데이트
          content.gsub!(/^(proxy:\s*\n\s*ssl:\s*true\s*\n\s*host:\s*)\S+/, "\\1#{final_domain}")
        elsif content.match?(/^# proxy:\s*$/m)
          # 주석 처리된 proxy 섹션이 있음 - 주석 해제하고 값 설정
          # 주의: m 플래그 없이 사용하여 .가 개행을 매칭하지 않도록 함
          content.gsub!(
            /^# proxy:\s*\n#\s+ssl:\s*true\s*\n#\s+host:\s*\S+/,
            "proxy:\n  ssl: true\n  host: #{final_domain}"
          )
        else
          # proxy 섹션이 없음 - registry 섹션 앞에 추가
          proxy_config = "proxy:\n  ssl: true\n  host: #{final_domain}\n\n"
          if content.match?(/^# Where you keep your container images/m)
            content.gsub!(/^# Where you keep your container images/, "#{proxy_config}# Where you keep your container images")
          else
            # registry 섹션 앞에 추가
            content.gsub!(/^registry:/, "#{proxy_config}registry:")
          end
        end

        # servers 설정 업데이트
        if content.match?(/servers:\s*\n\s*web:\s*\n\s*-\s*/)
          content.gsub!(/(\s*servers:\s*\n\s*web:\s*\n\s*-\s*)[\d.]+/, "\\1#{server_address}")
        end

        # ssh user 설정 업데이트
        if ssh_user && ssh_user != "root"
          if content.match?(/^ssh:/)
            # 기존 ssh 섹션 업데이트
            content.gsub!(/^ssh:\s*\n\s*user:\s*\w+/, "ssh:\n  user: #{ssh_user}")
          else
            # ssh 섹션 추가 (accessories 섹션 앞에 추가)
            if content.match?(/^# Use accessory services/)
              content.gsub!(/^# Use accessory services/, "# Use a different ssh user than root\nssh:\n  user: #{ssh_user}\n\n# Use accessory services")
            else
              # 파일 끝에 추가
              content += "\n# Use a different ssh user than root\nssh:\n  user: #{ssh_user}\n"
            end
          end
        end

        File.write(config_file, content)
        puts "✅ config/deploy.yml이 업데이트되었습니다.".colorize(:green)
        puts "   proxy.host: #{final_domain}".colorize(:gray)
        puts "   servers.web: #{server_address}".colorize(:gray)
        puts "   ssh.user: #{ssh_user}".colorize(:gray) if ssh_user && ssh_user != "root"
      end
      
      def commit_cloudflare_changes(domain_info)
        puts "\n📝 변경사항을 Git에 커밋합니다...".colorize(:yellow)
        
        # 변경된 파일이 있는지 확인
        status_output = `git status --porcelain`.strip
        
        if status_output.empty?
          puts "ℹ️  커밋할 변경사항이 없습니다.".colorize(:yellow)
          return
        end
        
        # Git add
        system("git add -A")
        
        # Commit 메시지 생성
        commit_message = "Configure Cloudflare DNS settings\n\n- Setup DNS for domain: #{domain_info[:domain]}\n- Configure server IP: #{domain_info[:server_ip]}\n- Update deployment configuration\n- Add proxy host settings\n\n🤖 Generated with Tayo"
        
        # Commit 실행
        if system("git commit -m \"#{commit_message}\"")
          puts "✅ 변경사항이 성공적으로 커밋되었습니다.".colorize(:green)
          
          # GitHub에 푸시
          if system("git push", out: File::NULL, err: File::NULL)
            puts "✅ 변경사항이 GitHub에 푸시되었습니다.".colorize(:green)
          else
            puts "⚠️  GitHub 푸시에 실패했습니다. 수동으로 'git push'를 실행해주세요.".colorize(:yellow)
          end
        else
          puts "❌ Git 커밋에 실패했습니다.".colorize(:red)
        end
      end
    end
  end
end