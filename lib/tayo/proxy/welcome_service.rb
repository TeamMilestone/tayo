# frozen_string_literal: true

require "colorize"
require "fileutils"

module Tayo
  module Proxy
    class WelcomeService
      def initialize
        @docker = DockerManager.new
      end

      def ensure_running
        # 호스트에서 3000 포트 서비스 확인 (Docker 제외)
        if host_port_in_use?(3000)
          puts "✅ 3000 포트에 호스트 서비스(Rails 등)가 실행 중입니다.".colorize(:green)

          # 기존 Welcome 컨테이너가 있다면 중지
          if @docker.container_running?("tayo-welcome")
            puts "🛑 기존 Welcome 서비스를 중지합니다...".colorize(:yellow)
            @docker.stop_container("tayo-welcome")
          end
          return
        end

        # Docker 컨테이너로 3000 포트가 사용 중인 경우
        if @docker.container_running?("tayo-welcome")
          puts "✅ Welcome 서비스가 이미 실행 중입니다.".colorize(:green)
          return
        end

        puts "\n🚀 3000 포트에 Welcome 서비스를 시작합니다...".colorize(:yellow)
        puts "   (Rails 서버를 시작하면 자동으로 중지됩니다)".colorize(:gray)

        prepare_welcome_files
        build_image
        start_container

        puts "✅ Welcome 서비스가 시작되었습니다.".colorize(:green)
      end

      private

      def host_port_in_use?(port)
        # macOS와 Linux에서 호스트 포트 확인 (Docker 컨테이너 제외)
        if RUBY_PLATFORM.include?("darwin")
          # macOS: lsof 사용, Docker 프로세스 제외
          output = `lsof -i :#{port} -sTCP:LISTEN 2>/dev/null | grep -v docker | grep -v com.docke | grep -v tayo-welcome`.strip
          !output.empty?
        else
          # Linux: netstat 또는 ss 사용
          output = `netstat -tln 2>/dev/null | grep ":#{port} " | grep -v docker`.strip
          if output.empty?
            output = `ss -tln 2>/dev/null | grep ":#{port} " | grep -v docker`.strip
          end
          !output.empty?
        end
      end

      def template_dir
        File.expand_path("../../../templates/welcome", __FILE__)
      end

      def prepare_welcome_files
        puts "📁 Welcome 서비스 파일을 준비합니다...".colorize(:yellow)

        # 템플릿 디렉토리 생성
        FileUtils.mkdir_p(template_dir)

        # Dockerfile 생성
        create_dockerfile

        # index.html 생성
        create_index_html
      end

      def create_dockerfile
        dockerfile_content = <<~DOCKERFILE
          FROM nginx:alpine

          # Nginx 설정
          RUN echo 'server { listen 80; root /usr/share/nginx/html; index index.html; location / { try_files $uri $uri/ =404; } }' > /etc/nginx/conf.d/default.conf

          # HTML 파일 복사
          COPY index.html /usr/share/nginx/html/

          # 헬스체크
          HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
            CMD wget --no-verbose --tries=1 --spider http://localhost || exit 1

          EXPOSE 80

          CMD ["nginx", "-g", "daemon off;"]
        DOCKERFILE

        File.write(File.join(template_dir, "Dockerfile"), dockerfile_content)
      end

      def create_index_html
        html_content = <<~HTML
          <!DOCTYPE html>
          <html lang="ko">
          <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>Tayo Proxy - Welcome</title>
              <style>
                  * {
                      margin: 0;
                      padding: 0;
                      box-sizing: border-box;
                  }

                  body {
                      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
                      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                      min-height: 100vh;
                      display: flex;
                      align-items: center;
                      justify-content: center;
                      color: white;
                      padding: 20px;
                  }

                  .container {
                      text-align: center;
                      max-width: 600px;
                      animation: fadeIn 1s ease-in;
                  }

                  @keyframes fadeIn {
                      from { opacity: 0; transform: translateY(-20px); }
                      to { opacity: 1; transform: translateY(0); }
                  }

                  .logo {
                      font-size: 5em;
                      margin-bottom: 20px;
                      animation: bounce 2s infinite;
                  }

                  @keyframes bounce {
                      0%, 100% { transform: translateY(0); }
                      50% { transform: translateY(-10px); }
                  }

                  h1 {
                      font-size: 3em;
                      margin-bottom: 20px;
                      font-weight: 700;
                      text-shadow: 2px 2px 4px rgba(0,0,0,0.2);
                  }

                  .subtitle {
                      font-size: 1.3em;
                      opacity: 0.95;
                      margin-bottom: 30px;
                      line-height: 1.5;
                  }

                  .status {
                      background: rgba(255, 255, 255, 0.2);
                      border-radius: 10px;
                      padding: 20px;
                      backdrop-filter: blur(10px);
                      margin-top: 30px;
                  }

                  .status-item {
                      display: flex;
                      justify-content: space-between;
                      padding: 10px 0;
                      border-bottom: 1px solid rgba(255, 255, 255, 0.1);
                  }

                  .status-item:last-child {
                      border-bottom: none;
                  }

                  .status-label {
                      font-weight: 600;
                  }

                  .status-value {
                      opacity: 0.9;
                  }

                  .status-ok {
                      color: #4ade80;
                  }

                  .info-box {
                      background: rgba(255, 255, 255, 0.1);
                      border-radius: 8px;
                      padding: 15px;
                      margin-top: 30px;
                      font-size: 0.9em;
                      opacity: 0.85;
                  }

                  .footer {
                      margin-top: 50px;
                      font-size: 0.85em;
                      opacity: 0.7;
                  }

                  .footer a {
                      color: white;
                      text-decoration: none;
                      border-bottom: 1px solid rgba(255, 255, 255, 0.3);
                      transition: border-color 0.3s;
                  }

                  .footer a:hover {
                      border-bottom-color: white;
                  }
              </style>
          </head>
          <body>
              <div class="container">
                  <div class="logo">🚀</div>
                  <h1>Tayo Proxy</h1>
                  <p class="subtitle">
                      홈서버 프록시 서비스가 정상적으로 작동 중입니다<br>
                      Your home server proxy is running successfully
                  </p>

                  <div class="status">
                      <div class="status-item">
                          <span class="status-label">프록시 상태</span>
                          <span class="status-value status-ok">✓ 활성</span>
                      </div>
                      <div class="status-item">
                          <span class="status-label">Kamal Proxy</span>
                          <span class="status-value status-ok">✓ 실행 중</span>
                      </div>
                      <div class="status-item">
                          <span class="status-label">Caddy Server</span>
                          <span class="status-value status-ok">✓ 실행 중</span>
                      </div>
                      <div class="status-item">
                          <span class="status-label">SSL/TLS</span>
                          <span class="status-value status-ok">✓ 준비됨</span>
                      </div>
                  </div>

                  <div class="info-box">
                      <strong>💡 다음 단계:</strong><br>
                      이제 실제 애플리케이션을 3000 포트에 배포하면<br>
                      이 페이지 대신 애플리케이션이 표시됩니다.
                  </div>

                  <div class="footer">
                      <p>
                          Powered by <a href="https://github.com/TeamMilestone/tayo" target="_blank">Tayo</a> |
                          <a href="https://kamal-deploy.org" target="_blank">Kamal</a> |
                          <a href="https://caddyserver.com" target="_blank">Caddy</a>
                      </p>
                  </div>
              </div>

              <script>
                  // 현재 시간 표시 (옵션)
                  const updateTime = () => {
                      const now = new Date();
                      const timeString = now.toLocaleTimeString('ko-KR');
                      // 시간 표시 기능이 필요한 경우 활성화
                  };
                  setInterval(updateTime, 1000);
                  updateTime();
              </script>
          </body>
          </html>
        HTML

        File.write(File.join(template_dir, "index.html"), html_content)
      end

      def build_image
        puts "🔨 Docker 이미지를 빌드합니다...".colorize(:yellow)

        cmd = "docker build -t tayo-welcome:latest #{template_dir}"

        if system(cmd)
          puts "✅ Docker 이미지 빌드가 완료되었습니다.".colorize(:green)
        else
          puts "❌ Docker 이미지 빌드에 실패했습니다.".colorize(:red)
          exit 1
        end
      end

      def start_container
        puts "🚀 Welcome 컨테이너를 시작합니다...".colorize(:yellow)

        # 기존 컨테이너가 있다면 제거
        if @docker.container_exists?("tayo-welcome")
          @docker.stop_container("tayo-welcome")
        end

        # 네트워크 확인
        network = @docker.create_network_if_not_exists("tayo-proxy")

        # Welcome 컨테이너 실행
        cmd = <<~DOCKER
          docker run -d \
            --name tayo-welcome \
            --network #{network} \
            -p 3000:80 \
            --restart unless-stopped \
            tayo-welcome:latest
        DOCKER

        if system(cmd)
          puts "✅ Welcome 서비스가 포트 3000에서 시작되었습니다.".colorize(:green)

          # 서비스 확인
          sleep 2
          check_service_health
        else
          puts "❌ Welcome 서비스 시작에 실패했습니다.".colorize(:red)
          exit 1
        end
      end

      def check_service_health
        # curl로 서비스 확인
        response = `curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null`.strip

        if response == "200"
          puts "✅ Welcome 서비스가 정상적으로 응답합니다.".colorize(:green)
        else
          puts "⚠️  Welcome 서비스 응답 확인 중... (HTTP #{response})".colorize(:yellow)
        end
      end
    end
  end
end