# 변경 이력

모든 주요 변경사항은 이 파일에 기록됩니다.

이 프로젝트는 [Semantic Versioning](https://semver.org/lang/ko/)을 따릅니다.

## [0.3.0] - 2026-01-11

### 제거됨
- `tayo proxy` 명령어 제거 - Kamal이 자동으로 Kamal Proxy를 관리하므로 불필요

### 개선됨
- **tayo cf**: Cloudflare 토큰 저장 및 재사용 기능
  - 환경변수 `CLOUDFLARE_API_TOKEN` 지원
  - `~/.config/tayo/cloudflare_token`에 토큰 자동 저장
  - 저장된 토큰 유효성 검사 후 재사용
- **tayo cf**: 홈서버 정보 저장 및 재사용 기능
  - `~/.config/tayo/server.yml`에 서버 정보 저장
  - 저장된 정보 표시 후 사용 여부 확인
- **tayo gh**: deploy.yml 설정 버그 수정
  - 주석 처리된 registry username/password 활성화 수정
  - image 이름에서 ghcr.io 중복 제거
- **tayo gh**: .kamal/secrets 설정 개선
  - `KAMAL_REGISTRY_PASSWORD=$(gh auth token)` 형식으로 동적 토큰 사용
  - 주석 처리된 라인과 실제 설정 라인 구분

## [0.2.0] - 2025-09-28

### 추가됨
- 새로운 `tayo proxy` 명령어 - 고급 프록시 서버 설정 기능
- Traefik 기반 리버스 프록시와 자동 SSL 관리
- Docker Compose를 통한 편리한 컨테이너 관리
- 멀티 도메인 라우팅 지원
- Let's Encrypt를 통한 자동 SSL 인증서 발급 및 갱신
- 기본 랜딩 페이지를 위한 Welcome 서비스
- 도메인 관리를 위한 Cloudflare DNS 통합
- Docker 컨테이너와 호스트 서비스 모두 지원 (host.docker.internal)
- Traefik 대시보드 제공 (http://localhost:8080, admin/admin)
- 공유기 포트포워딩 설정 지원 (80/443 또는 커스텀 포트)

### 개선됨
- Welcome 서비스의 호스트 포트 감지 개선
- Rails 개발 서버 우선순위 처리
- 프록시 아키텍처 문서 개선

## [0.1.11] - 2025-06-18

### 개선됨
- Gemfile 수정 제거 및 초기화 워크플로우 개선
- bootsnap 처리를 DockerfileModifier 클래스로 리팩토링

## [0.1.10] - 2025-06-17

### 추가됨
- 버전 표시 및 디버깅 기능
- bootsnap 제거에 대한 포괄적인 테스트
- 엣지 케이스 수정

### 개선됨
- reject 패턴 매칭으로 bootsnap 제거 단순화

## [0.1.0] - 2025-06-17

### 추가됨
- `tayo init` - Rails 프로젝트 초기화 명령어
  - OrbStack 설치 확인
  - Linux 플랫폼 추가 (x86_64-linux, aarch64-linux)
  - Dockerfile 자동 생성
  - Welcome 페이지 생성
  - 자동 Git 커밋
  - Docker 캐시 정리

- `tayo gh` - GitHub 저장소 및 Container Registry 설정
  - GitHub CLI 인증 확인
  - 저장소 생성/연결
  - GitHub Container Registry 설정
  - deploy.yml 설정 파일 생성

- `tayo cf` - Cloudflare DNS 설정
  - API 토큰 관리 (macOS Keychain 사용)
  - 도메인 Zone 자동 감지
  - DNS A 레코드 생성/업데이트

[0.3.0]: https://github.com/TeamMilestone/tayo/compare/v0.2.3...v0.3.0
[0.2.0]: https://github.com/TeamMilestone/tayo/compare/v0.1.11...v0.2.0
[0.1.11]: https://github.com/TeamMilestone/tayo/compare/v0.1.10...v0.1.11
[0.1.10]: https://github.com/TeamMilestone/tayo/compare/v0.1.0...v0.1.10
[0.1.0]: https://github.com/TeamMilestone/tayo/releases/tag/v0.1.0