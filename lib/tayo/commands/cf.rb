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

        # --- 로직 순서 변경 ---
        
        # 2. 토큰 입력받기
        token = get_cloudflare_token
        
        # 3. Cloudflare 존 선택 및 도메인 구성 (새로운 방식)
        domain_info = configure_domain_from_zones(token)
        selected_zone = domain_info[:selected_zone_object]

        # 4. 기존 DNS 레코드 확인 (참고용)
        existing_records = check_existing_records(token, selected_zone, domain_info)
        
        # 5. DNS 레코드 추가/수정 (루트 도메인 덮어쓰기 로직 포함)
        setup_dns_record(token, selected_zone, domain_info, existing_records)
        
        # 6. config/deploy.yml 업데이트
        update_deploy_config(domain_info)

        puts "\n🎉 Cloudflare DNS 설정이 완료되었습니다!".colorize(:green)
        
        # 7. 변경사항 커밋
        commit_cloudflare_changes(domain_info)
      end

      private

      def rails_project?
        File.exist?("Gemfile") && File.exist?("config/application.rb")
      end

      # [신규] Cloudflare Zone 목록에서 도메인을 선택하고 구성하는 메소드
      def configure_domain_from_zones(token)
        puts "\n🌐 Cloudflare 계정의 도메인 목록을 조회합니다...".colorize(:yellow)
        
        zones = get_cloudflare_zones(token)
        
        if zones.empty?
          puts "❌ Cloudflare에 등록된 도메인(Zone)이 없습니다.".colorize(:red)
          puts "먼저 https://dash.cloudflare.com 에서 도메인을 추가해주세요.".colorize(:cyan)
          exit 1
        end
        
        prompt = TTY::Prompt.new
        # 사용자가 Zone을 이름으로 선택하고, 선택 시 전체 Zone 객체를 반환하도록 설정
        zone_choices = zones.map { |zone| { name: "#{zone['name']} (#{zone['status']})", value: zone } }
        
        selected_zone = prompt.select("설정할 도메인(Zone)을 선택하세요:", zone_choices, filter: true, per_page: 10)
        zone_name = selected_zone['name']
        puts "✅ 선택된 Zone: #{zone_name}".colorize(:green)

        domain_type = prompt.select("\n어떤 종류의 도메인을 설정하시겠습니까?", [
          { name: "루트 도메인 (@) - 예: #{zone_name}", value: :root },
          { name: "서브도메인 - 예: www.#{zone_name}", value: :subdomain }
        ])

        if domain_type == :root
          return {
            type: :root,
            domain: zone_name,
            zone: zone_name,
            selected_zone_object: selected_zone
          }
        else # :subdomain
          subdomain_part = prompt.ask("사용할 서브도메인을 입력하세요 (예: www, api):") do |q|
            q.required true
            q.validate(/^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/, "유효한 서브도메인을 입력해주세요 (특수문자, . 사용 불가)")
          end

          full_domain = "#{subdomain_part.downcase}.#{zone_name}"
          puts "✅ 설정할 전체 도메인: #{full_domain}".colorize(:green)

          return {
            type: :subdomain,
            domain: full_domain,
            zone: zone_name,
            subdomain: subdomain_part.downcase,
            selected_zone_object: selected_zone
          }
        end
      end

      def open_token_creation_page
        puts "\n🔑 Cloudflare API 토큰이 필요합니다.".colorize(:yellow)
        
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

        puts "토큰 생성 페이지를 엽니다...".colorize(:cyan)
        
        system("open 'https://dash.cloudflare.com/profile/api-tokens'")        
      end

      def get_cloudflare_token
        existing_token = load_saved_token
        
        if existing_token
          puts "💾 저장된 토큰을 발견했습니다.".colorize(:cyan)
          if test_cloudflare_token(existing_token)
            puts "✅ 저장된 토큰이 유효합니다.".colorize(:green)
            return existing_token
          else
            puts "❌ 저장된 토큰이 만료되거나 무효합니다. 새 토큰을 입력해주세요.".colorize(:yellow)
            open_token_creation_page
          end
        else
          open_token_creation_page
        end
        
        prompt = TTY::Prompt.new
        
        token = prompt.mask("생성된 Cloudflare API 토큰을 붙여넣으세요:")
        
        if token.nil? || token.strip.empty?
          puts "❌ 토큰이 입력되지 않았습니다.".colorize(:red)
          exit 1
        end
        
        if test_cloudflare_token(token.strip)
          puts "✅ 토큰이 확인되었습니다.".colorize(:green)
          save_token(token.strip)
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

      def load_saved_token
        token_file = File.expand_path("~/.tayo")
        return nil unless File.exist?(token_file)
        
        begin
          content = File.read(token_file)
          token_line = content.lines.find { |line| line.start_with?("CLOUDFLARE_TOKEN=") }
          return nil unless token_line
          
          token = token_line.split("=", 2)[1]&.strip
          return token unless token.nil? || token.empty?
          
          nil
        rescue => e
          puts "⚠️  토큰 파일 읽기 중 오류가 발생했습니다: #{e.message}".colorize(:yellow)
          nil
        end
      end

      def save_token(token)
        token_file = File.expand_path("~/.tayo")
        timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
        
        content = <<~CONTENT
          # Tayo Configuration File
          # Created: #{timestamp}
          CLOUDFLARE_TOKEN=#{token}
        CONTENT
        
        begin
          File.write(token_file, content)
          File.chmod(0600, token_file)
          puts "💾 토큰이 ~/.tayo 파일에 저장되었습니다.".colorize(:green)
        rescue => e
          puts "⚠️  토큰 저장 중 오류가 발생했습니다: #{e.message}".colorize(:yellow)
        end
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
        
        target_name = (domain_info[:type] == :root) ? zone['name'] : domain_info[:domain]
        records = get_dns_records(token, zone['id'], target_name, ['A', 'CNAME'])
        
        puts "   (확인 대상: #{target_name}, 발견된 A/CNAME 레코드: #{records.length}개)".colorize(:gray)
        
        return records
      end

      def get_dns_records(token, zone_id, name, types)
        records = []
        
        types.each do |type|
          uri = URI("https://api.cloudflare.com/client/v4/zones/#{zone_id}/dns_records")
          uri.query = URI.encode_www_form({ type: type, name: name })
          
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
        
        prompt = TTY::Prompt.new
        
        server_info = prompt.ask("연결할 서버 IP 또는 도메인을 입력하세요:") do |q|
          q.validate(/\A.+\z/, "서버 정보를 입력해주세요")
        end
        
        ssh_user = prompt.ask("SSH 사용자 계정을 입력하세요:", default: "root")
        
        is_ip = server_info.match?(/\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/)
        record_type = is_ip ? 'A' : 'CNAME'
        
        zone_id = zone['id']
        zone_name = zone['name']
        
        final_domain = determine_final_domain(domain_info, zone_name, existing_records)
        all_records = get_dns_records(token, zone_id, final_domain[:name], ['A', 'CNAME'])
        
        is_already_configured = all_records.length == 1 &&
                               all_records.first['type'] == record_type &&
                               all_records.first['content'] == server_info

        if is_already_configured
          puts "✅ DNS 레코드가 이미 올바르게 설정되어 있습니다.".colorize(:green)
          puts "   #{final_domain[:full_domain]} → #{server_info} (#{record_type} 레코드)".colorize(:gray)
        else
          # [수정됨] 기존 레코드가 있으면 사용자에게 확인을 받습니다.
          if all_records.any?
            puts "\n⚠️  '#{final_domain[:full_domain]}'에 이미 설정된 DNS 레코드가 있습니다.".colorize(:yellow)
            puts "--------------------------------------------------"
            all_records.each do |record|
              puts "  - 타입: ".ljust(10) + "#{record['type']}".colorize(:cyan)
              puts "    내용: ".ljust(10) + "#{record['content']}".colorize(:cyan)
              puts "    프록시: ".ljust(10) + "#{record['proxied'] ? '활성' : '비활성'}".colorize(:cyan)
              puts " "
            end
            puts "--------------------------------------------------"

            message = "이 레코드를 삭제하고 새로 설정하시겠습니까? (이 작업은 되돌릴 수 없습니다)"
            unless prompt.yes?(message)
              puts "❌ DNS 설정이 사용자에 의해 취소되었습니다. 스크립트를 종료합니다.".colorize(:red)
              exit 0
            end
            
            puts "\n✅ 사용자가 승인하여 기존 레코드를 삭제하고 새 레코드를 생성합니다.".colorize(:green)
            all_records.each do |record|
              delete_dns_record(token, zone_id, record['id'])
            end
            create_dns_record(token, zone_id, final_domain[:name], record_type, server_info)

          else
            # 기존 레코드가 없으면 바로 생성합니다.
            create_dns_record(token, zone_id, final_domain[:name], record_type, server_info)
          end
        end
        
        @final_domain = final_domain[:full_domain]
        @server_info = server_info
        @ssh_user = ssh_user
      end
      
      def determine_final_domain(domain_info, zone_name, existing_records)
        case domain_info[:type]
        when :root
          { name: zone_name, full_domain: zone_name }
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
          ttl: 300,
          proxied: true
        }
        
        request.body = data.to_json
        response = http.request(request)
        
        if response.code == '200'
          puts "✅ DNS 레코드가 생성되었습니다.".colorize(:green)
          puts "   #{name} → #{content} (#{type} 레코드, 프록시됨)".colorize(:gray)
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
        
        unless response.code == '200'
          puts "❌ DNS 레코드 삭제에 실패했습니다: #{response.code}".colorize(:red)
          puts response.body
        end
      rescue => e
        puts "❌ DNS 레코드 삭제 중 오류: #{e.message}".colorize(:red)
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
          proxy_config = "\n# Proxy configuration\nproxy:\n  ssl: true\n  host: #{@final_domain}\n"
          content += proxy_config
        end
        
        # servers 설정 업데이트
        if content.match?(/servers:\s*\n\s*web:\s*\n\s*-\s*/)
          content.gsub!(/(\s*servers:\s*\n\s*web:\s*\n\s*-\s*)[\w.-]+/, "\\1#{@server_info}")
        end
        
        # ssh user 설정 업데이트
        if @ssh_user && @ssh_user != "root"
          if content.match?(/^ssh:/)
            content.gsub!(/^ssh:\s*\n\s*user:\s*\w+/, "ssh:\n  user: #{@ssh_user}")
          else
            if content.match?(/^# Use accessory services/)
              content.gsub!(/^# Use accessory services/, "# Use a different ssh user than root\nssh:\n  user: #{@ssh_user}\n\n# Use accessory services")
            else
              content += "\n# Use a different ssh user than root\nssh:\n  user: #{@ssh_user}\n"
            end
          end
        end
        
        File.write(config_file, content)
        puts "✅ config/deploy.yml이 업데이트되었습니다.".colorize(:green)
        puts "   proxy.host: #{@final_domain}".colorize(:gray)
        puts "   servers.web: #{@server_info}".colorize(:gray)
        if @ssh_user && @ssh_user != "root"
          puts "   ssh.user: #{@ssh_user}".colorize(:gray)
        end
      end
      
      def commit_cloudflare_changes(domain_info)
        puts "\n📝 변경사항을 Git에 커밋합니다...".colorize(:yellow)
        
        status_output = `git status --porcelain config/deploy.yml`.strip
        
        if status_output.empty?
          puts "ℹ️  커밋할 변경사항이 없습니다.".colorize(:cyan)
          return
        end
        
        system("git add config/deploy.yml")
        
        commit_message = "feat: Configure Cloudflare DNS for #{@final_domain}\n\n- Set DNS record for #{@final_domain} to point to #{@server_info}\n- Update deployment configuration in config/deploy.yml\n\n🤖 Generated by Tayo"
        
        if system("git commit -m \"#{commit_message}\"")
          puts "✅ 변경사항이 성공적으로 커밋되었습니다.".colorize(:green)
          
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