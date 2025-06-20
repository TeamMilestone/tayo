# Tayo

Rails 애플리케이션을 홈서버에 배포하기 위한 도구입니다. GitHub Container Registry와 Cloudflare를 활용하여 간편한 배포 워크플로우를 제공합니다.

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
- **Dockerfile 생성**: Rails 7 기본 Dockerfile이 없으면 생성합니다
- **Welcome 페이지 생성**: 
  - `app/controllers/welcome_controller.rb` 컨트롤러 생성
  - `app/views/welcome/index.html.erb` 뷰 파일 생성 (애니메이션이 있는 예쁜 랜딩 페이지)
  - `config/routes.rb`에 `root 'welcome#index'` 설정 추가
- **Docker 캐시 정리**: 디스크 공간 확보를 위해 Docker 캐시를 정리합니다
- **Git 커밋**: 변경사항을 자동으로 커밋합니다

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
  - 개인 계정 및 조직(Organization) 계정 모두 지원
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
- **Git 커밋**: 설정 변경사항을 자동으로 커밋합니다

### 3. `tayo cf` - Cloudflare DNS 설정

Cloudflare를 통해 도메인을 홈서버 IP에 연결합니다.

```bash
tayo cf
```

이 명령어는 다음 작업들을 수행합니다:

- **Cloudflare 인증**:
  - API 토큰 입력 요청 (처음 실행 시)
  - 토큰을 `~/.tayo` 파일에 안전하게 저장하여 재사용
  - 필요한 권한: Zone:Read, DNS:Edit
- **도메인 설정**: 
  - Cloudflare 계정의 Zone 목록에서 도메인 선택
  - 루트 도메인(@) 또는 서브도메인 설정 지원
  - 대화형 UI로 쉽게 설정 가능
- **DNS 레코드 생성/업데이트**:
  - A 레코드 생성: IP 주소로 연결
  - CNAME 레코드 생성: 도메인으로 연결
  - 기존 레코드가 있으면 사용자 확인 후 업데이트
  - Proxied 설정 (Cloudflare CDN 사용)
- **배포 설정 업데이트**:
  - `config/deploy.yml` 파일의 proxy.host 자동 업데이트
  - 서버 정보 및 SSH 사용자 설정
- **Git 커밋**: DNS 설정 변경사항을 자동으로 커밋합니다

## 전체 워크플로우

```bash
# 1. 새 Rails 프로젝트 생성
rails new myapp
cd myapp

# 2. Tayo로 배포 준비
tayo init    # Rails 프로젝트 초기화
tayo gh      # GitHub 저장소 및 Container Registry 설정
tayo cf      # Cloudflare DNS 설정

# 3. Kamal로 배포
bin/kamal setup
```

## 주요 기능

- **🚀 원스톱 배포 설정**: 3개의 명령어로 배포 준비 완료
- **🐳 Docker 기반**: OrbStack과 GitHub Container Registry 활용
- **🌐 Cloudflare 통합**: 자동 DNS 설정 및 CDN 지원
- **🔒 보안**: 토큰과 환경 변수를 안전하게 관리
- **🎯 한국어 UI**: 모든 메시지가 한국어로 제공
- **🛡️ 오류 처리**: 각 단계별 검증과 친절한 오류 메시지

## 요구사항

- Ruby 3.1.0 이상
- Rails 7.0 이상
- macOS (OrbStack 사용)
- GitHub 계정
- Cloudflare 계정

## 라이선스

MIT License