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
  - `.kamal/secrets`에 `KAMAL_REGISTRY_PASSWORD` 자동 설정
- **배포 설정 파일 업데이트**:
  - `config/deploy.yml` 파일의 image, registry 설정 업데이트

### 3. `tayo cf` - Cloudflare DNS 설정

Cloudflare를 통해 도메인을 홈서버 IP에 연결합니다.

```bash
tayo cf
```

이 명령어는 다음 작업들을 수행합니다:

- **Cloudflare 인증**:
  - 저장된 토큰 확인 (`~/.config/tayo/cloudflare_token`)
  - 환경변수 `CLOUDFLARE_API_TOKEN` 지원
  - 토큰이 없거나 유효하지 않으면 생성 페이지 열고 입력 받음
  - 유효한 토큰은 자동 저장 (다음 실행 시 재사용)
- **도메인 Zone 선택**:
  - Cloudflare 계정의 도메인 목록 표시
  - Zone ID 자동 가져오기
- **기존 DNS 레코드 표시**:
  - 선택한 Zone의 A/CNAME 레코드 목록 표시
- **서비스 도메인 설정**:
  - 루트 도메인 또는 서브도메인 선택
- **홈서버 연결 정보**:
  - 저장된 정보가 있으면 확인 후 재사용 (`~/.config/tayo/server.yml`)
  - 없으면 IP/도메인과 SSH 사용자 입력 받아 저장
- **DNS 레코드 생성/업데이트**:
  - A 레코드 (IP) 또는 CNAME 레코드 (도메인) 자동 선택
  - 기존 레코드가 있으면 업데이트
- **deploy.yml 업데이트**:
  - `servers.web` 호스트 설정
  - `proxy` 섹션 (SSL 및 도메인) 설정
  - `ssh.user` 설정

### 4. `tayo sqlite` - SQLite 최적화 (Solid Cable용)

Solid Cable과 SQLite를 함께 사용할 때 필요한 최적화 설정을 적용합니다.

```bash
tayo sqlite
```

이 명령어는 다음 작업들을 수행합니다:

- **SQLite WAL 모드 설정**: database.yml에 WAL 저널 모드 추가
- **연결 설정 최적화**: idle_timeout, checkout_timeout, pool 설정

## 사용 예시

### Rails 앱 배포
```bash
rails new myapp
cd myapp
tayo init
tayo gh
tayo cf
bin/kamal setup
```

## 저장되는 설정 파일

| 파일 | 용도 |
|------|------|
| `~/.config/tayo/cloudflare_token` | Cloudflare API 토큰 |
| `~/.config/tayo/server.yml` | 홈서버 연결 정보 (IP, SSH 사용자) |
