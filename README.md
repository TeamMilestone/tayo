# Tayo

Rails 애플리케이션을 홈서버에 배포하기 위한 도구입니다.

## 설치

시스템 와이드로 설치:

```bash
gem install tayo
```

## 사용법

### 1. `tayo init` - Rails 프로젝트 초기화

Rails 프로젝트를 홈서버 배포를 위해 준비합니다.

```bash
tayo init
```

이 명령어는 다음 작업들을 수행합니다:

- **OrbStack 설치 확인**: Docker 컨테이너를 실행하기 위한 OrbStack이 설치되어 있는지 확인합니다
- **Gemfile 수정**: development 그룹에 tayo gem을 추가합니다
- **Bundle 설치**: 의존성을 설치합니다
- **Linux 플랫폼 추가**: `x86_64-linux`와 `aarch64-linux` 플랫폼을 Gemfile.lock에 추가합니다
- **Dockerfile 생성**: Rails 7 기본 Dockerfile이 없으면 생성합니다
- **Welcome 페이지 생성**: 
  - `app/controllers/welcome_controller.rb` 컨트롤러 생성
  - `app/views/welcome/index.html.erb` 뷰 파일 생성 (애니메이션이 있는 예쁜 랜딩 페이지)
  - `config/routes.rb`에 `root 'welcome#index'` 설정 추가
- **Git 커밋**: 변경사항을 자동으로 커밋합니다
- **Docker 캐시 정리**: 디스크 공간 확보를 위해 Docker 캐시를 정리합니다

### 2. `tayo gh` - GitHub 저장소 및 Container Registry 설정

GitHub 저장소를 생성하고 Container Registry를 설정합니다.

```bash
tayo gh
```

이 명령어는 다음 작업들을 수행합니다:

- **GitHub CLI 설치 확인**: `gh` 명령어가 설치되어 있는지 확인합니다
- **GitHub 인증 확인**: 
  - GitHub에 로그인되어 있는지 확인
  - 필요한 권한(repo, read:org, write:packages) 확인
  - 권한이 없으면 브라우저에서 토큰 생성 페이지를 엽니다
- **Git 저장소 초기화**: 아직 git 저장소가 아니면 초기화합니다
- **GitHub 원격 저장소 설정**:
  - 기존 원격 저장소가 있으면 사용
  - 없으면 새 저장소 생성 (public/private 선택 가능)
  - 코드를 GitHub에 푸시
- **GitHub Container Registry 설정**:
  - Registry URL 생성: `ghcr.io/username/repository-name`
  - Docker로 자동 로그인 실행
- **배포 설정 파일 생성**:
  - `config/deploy.yml` 파일 생성 또는 업데이트
  - 서버 IP, 도메인, 데이터베이스 등 설정 포함
- **환경 변수 파일 준비**:
  - `.env.production` 파일 생성
  - `.gitignore`에 추가하여 보안 유지

### 3. `tayo cf` - Cloudflare DNS 설정

Cloudflare를 통해 도메인을 홈서버 IP에 연결합니다.

```bash
tayo cf
```

이 명령어는 다음 작업들을 수행합니다:

- **설정 파일 확인**: `config/deploy.yml` 파일에서 서버 IP와 도메인 정보를 읽습니다
- **Cloudflare 인증**:
  - API 토큰 입력 요청 (처음 실행 시)
  - 토큰을 안전하게 저장 (macOS Keychain 사용)
- **도메인 Zone 확인**: 
  - Cloudflare 계정에서 도메인을 찾습니다
  - Zone ID를 자동으로 가져옵니다
- **DNS 레코드 생성/업데이트**:
  - A 레코드 생성: 도메인을 서버 IP에 연결
  - 기존 레코드가 있으면 업데이트
  - Proxied 설정 (Cloudflare CDN 사용)
- **설정 완료 확인**:
  - DNS 설정이 완료되면 성공 메시지 표시
  - 도메인으로 접속 가능함을 안내

각 명령어는 단계별로 진행 상황을 표시하며, 오류가 발생하면 친절한 안내 메시지를 제공합니다.

rails new 로 프로젝트 생성 후 
bundle exec tayo init
bundle exec tayo gh
bundle exec tayo cf

순으로 진행 후
bin/kamal setup 으로 배포 진행