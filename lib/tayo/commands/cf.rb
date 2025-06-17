# frozen_string_literal: true

require "colorize"
require "tty-prompt"
require "net/http"
require "json"
require "uri"

module Tayo
  module Commands
    class Cf
      def execute
        puts "☁️  Cloudflare DNS 설정을 시작합니다...".colorize(:green)

        unless rails_project?
          puts "❌ Rails 프로젝트가 아닙니다. Rails 프로젝트 루트에서 실행해주세요.".colorize(:red)
          return
        end

        # 1. 도메인 입력받기
        domain_info = get_domain_input
        
        # 2. Cloudflare 토큰 생성 페이지 열기 및 권한 안내
        open_token_creation_page
        
        # 3. 토큰 입력받기
        token = get_cloudflare_token
        
        # 4. Cloudflare API로 도메인 목록 조회 및 선택
        selected_zone = select_cloudflare_zone(token)
        
        # 5. 루트 도메인 레코드 확인
        existing_records = check_existing_records(token, selected_zone, domain_info)
        
        # 6. DNS 레코드 추가/수정
        setup_dns_record(token, selected_zone, domain_info, existing_records)
        
        # 7. config/deploy.yml 업데이트
        update_deploy_config(domain_info)

        puts "\n🎉 Cloudflare DNS 설정이 완료되었습니다!".colorize(:green)
        
        # 변경사항 커밋
        commit_cloudflare_changes(domain_info)
      end

      private

      def rails_project?
        File.exist?("Gemfile") && File.exist?("config/application.rb")
      end

      def get_domain_input
        prompt = TTY::Prompt.new
        
        puts "\n📝 배포할 도메인을 설정합니다.".colorize(:yellow)
        
        domain = prompt.ask("배포할 도메인을 입력하세요 (예: myapp.com, api.example.com):") do |q|
          q.validate(/\A[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\z/, "올바른 도메인 형식을 입력해주세요 (예: myapp.com)")
        end
        
        # 도메인이 루트인지 서브도메인인지 판단
        parts = domain.split('.')
        if parts.length == 2
          { type: :root, domain: domain, zone: domain }
        else
          zone = parts[-2..-1].join('.')
          { type: :subdomain, domain: domain, zone: zone, subdomain: parts[0..-3].join('.') }
        end
      end

      def open_token_creation_page
        puts "\n🔑 Cloudflare API 토큰이 필요합니다.".colorize(:yellow)
        puts "토큰 생성 페이지를 엽니다...".colorize(:cyan)
        
        # Cloudflare API 토큰 생성 페이지 열기
        system("open 'https://dash.cloudflare.com/profile/api-tokens'")
        
        puts "\n다음 권한으로 토큰을 생성해주세요:".colorize(:yellow)
        puts ""
        puts "한국어 화면:".colorize(:gray)
        puts "• 영역 → DNS → 읽기".colorize(:white)
        puts "• 영역 → DNS → 편집".colorize(:white)
        puts "  (영역 리소스는 '모든 영역' 선택)".colorize(:gray)
        puts ""
        puts "English:".colorize(:gray)
        puts "• Zone → DNS → Read".colorize(:white)
        puts "• Zone → DNS → Edit".colorize(:white)
        puts "  (Zone Resources: Select 'All zones')".colorize(:gray)
        puts ""
      end

      def get_cloudflare_token
        prompt = TTY::Prompt.new
        
        token = prompt.mask("생성된 Cloudflare API 토큰을 붙여넣으세요:")
        
        if token.nil? || token.strip.empty?
          puts "❌ 토큰이 입력되지 않았습니다.".colorize(:red)
          exit 1
        end
        
        # 토큰 유효성 간단 확인
        if test_cloudflare_token(token.strip)
          puts "✅ 토큰이 확인되었습니다.".colorize(:green)
          return token.strip
        else
          puts "❌ 토큰이 올바르지 않거나 권한이 부족합니다.".colorize(:red)
          exit 1
        end
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

      def check_existing_records(token, zone, domain_info)
        puts "\n🔍 기존 DNS 레코드를 확인합니다...".colorize(:yellow)
        
        zone_id = zone['id']
        zone_name = zone['name']
        
        # 루트 도메인의 A/CNAME 레코드 확인
        records = get_dns_records(token, zone_id, zone_name, ['A', 'CNAME'])
        
        puts "기존 레코드: #{records.length}개 발견".colorize(:gray)
        
        return records
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

      def setup_dns_record(token, zone, domain_info, existing_records)
        puts "\n⚙️  DNS 레코드를 설정합니다...".colorize(:yellow)
        
        # 홈서버 IP/URL 입력받기
        prompt = TTY::Prompt.new
        
        server_info = prompt.ask("홈서버 IP 또는 도메인을 입력하세요:") do |q|
          q.validate(/\A.+\z/, "서버 정보를 입력해주세요")
        end
        
        # SSH 사용자 계정 입력받기
        ssh_user = prompt.ask("SSH 사용자 계정을 입력하세요:", default: "root")
        
        # IP인지 도메인인지 판단
        is_ip = server_info.match?(/\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/)
        record_type = is_ip ? 'A' : 'CNAME'
        
        zone_id = zone['id']
        zone_name = zone['name']
        
        # 도메인 정보에 따라 레코드 설정
        final_domain = determine_final_domain(domain_info, zone_name, existing_records)
        
        # 대상 도메인의 모든 A/CNAME 레코드 확인
        all_records = get_dns_records(token, zone_id, final_domain[:name], ['A', 'CNAME'])
        
        if all_records.any?
          existing_record = all_records.first
          
          # 동일한 타입이고 같은 값이면 건너뛰기
          if existing_record['type'] == record_type && existing_record['content'] == server_info
            puts "✅ DNS 레코드가 이미 올바르게 설정되어 있습니다.".colorize(:green)
            puts "   #{final_domain[:full_domain]} → #{server_info} (#{record_type} 레코드)".colorize(:gray)
          else
            # 타입이 다르거나 값이 다른 경우 삭제 후 재생성
            puts "⚠️  기존 레코드를 삭제하고 새로 생성합니다.".colorize(:yellow)
            puts "   기존: #{existing_record['content']} (#{existing_record['type']}) → 새로운: #{server_info} (#{record_type})".colorize(:gray)
            
            # 기존 레코드 삭제
            delete_dns_record(token, zone_id, existing_record['id'])
            
            # 새 레코드 생성
            create_dns_record(token, zone_id, final_domain[:name], record_type, server_info)
          end
        else
          # DNS 레코드 생성
          create_dns_record(token, zone_id, final_domain[:name], record_type, server_info)
        end
        
        # 최종 도메인 정보 저장
        @final_domain = final_domain[:full_domain]
        @server_info = server_info
        @ssh_user = ssh_user
      end

      def determine_final_domain(domain_info, zone_name, existing_records)
        case domain_info[:type]
        when :root
          if existing_records.any?
            puts "⚠️  루트 도메인에 이미 레코드가 있습니다. app.#{zone_name}을 사용합니다.".colorize(:yellow)
            { name: "app.#{zone_name}", full_domain: "app.#{zone_name}" }
          else
            { name: zone_name, full_domain: zone_name }
          end
        when :subdomain
          { name: domain_info[:domain], full_domain: domain_info[:domain] }
        end
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

      def update_deploy_config(domain_info)
        puts "\n📝 배포 설정을 업데이트합니다...".colorize(:yellow)
        
        config_file = "config/deploy.yml"
        
        unless File.exist?(config_file)
          puts "⚠️  config/deploy.yml 파일이 없습니다.".colorize(:yellow)
          return
        end
        
        content = File.read(config_file)
        
        # proxy.host 설정 업데이트
        if content.include?("proxy:")
          content.gsub!(/(\s+host:\s+).*$/, "\\1#{@final_domain}")
        else
          # proxy 섹션이 없으면 추가
          proxy_config = "\n# Proxy configuration\nproxy:\n  ssl: true\n  host: #{@final_domain}\n"
          content += proxy_config
        end
        
        # servers 설정 업데이트
        if content.match?(/servers:\s*\n\s*web:\s*\n\s*-\s*/)
          content.gsub!(/(\s*servers:\s*\n\s*web:\s*\n\s*-\s*)[\d.]+/, "\\1#{@server_info}")
        end
        
        # ssh user 설정 업데이트
        if @ssh_user && @ssh_user != "root"
          if content.match?(/^ssh:/)
            # 기존 ssh 섹션 업데이트
            content.gsub!(/^ssh:\s*\n\s*user:\s*\w+/, "ssh:\n  user: #{@ssh_user}")
          else
            # ssh 섹션 추가 (accessories 섹션 앞에 추가)
            if content.match?(/^# Use accessory services/)
              content.gsub!(/^# Use accessory services/, "# Use a different ssh user than root\nssh:\n  user: #{@ssh_user}\n\n# Use accessory services")
            else
              # 파일 끝에 추가
              content += "\n# Use a different ssh user than root\nssh:\n  user: #{@ssh_user}\n"
            end
          end
        end
        
        File.write(config_file, content)
        puts "✅ config/deploy.yml이 업데이트되었습니다.".colorize(:green)
        puts "   proxy.host: #{@final_domain}".colorize(:gray)
        puts "   servers.web: #{@server_info}".colorize(:gray)
        puts "   ssh.user: #{@ssh_user}".colorize(:gray) if @ssh_user && @ssh_user != "root"
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