# 변경 기록 (Changelog)

## [0.1.12] - 2025-01-20

### 🚀 새로운 기능
- **CLAUDE.md 문서 지원**: Claude AI 도우미를 위한 프로젝트별 지침 파일 지원
- **Cloudflare DNS 설정 대폭 개선**:
  - Cloudflare Zone 목록에서 도메인을 직접 선택하는 방식으로 변경
  - 루트 도메인(@)과 서브도메인 선택 UI 개선
  - 기존 DNS 레코드 확인 및 덮어쓰기 시 사용자 확인 프롬프트 추가
  - Cloudflare API 토큰을 `~/.tayo` 파일에 안전하게 저장 및 재사용
- **자동 Git 커밋**: `tayo gh`와 `tayo cf` 명령어 실행 후 자동으로 변경사항 커밋
- **버전 표시**: 명령어 실행 시 Tayo 버전 표시

### 🛠️ 개선사항
- **Init 워크플로우 간소화**:
  - Gemfile 수정 제거로 더 깔끔한 초기화 프로세스
  - Docker 캐시 정리 기능 추가
  - bootsnap 자동 처리 제거 (안정성 문제로 인해)
- **GitHub Container Registry 설정**:
  - 조직(Organization) 계정 지원 추가
  - ghcr.io URL 중복 제거 버그 수정
  - Docker 로그인 자동화

### 🐛 버그 수정
- Dockerfile bootsnap 프리컴파일 이슈 수정
- DNS 레코드 생성 시 프록시 설정 누락 문제 해결

## [0.1.11] - 2025-01-19

### 🛠️ 개선사항
- Bootsnap 처리를 DockerfileModifier 클래스로 리팩토링
- 더 안정적인 bootsnap 라인 제거 로직 구현
- 테스트 커버리지 강화

## [0.1.10] - 2025-01-18

### 🚀 새로운 기능
- Dockerfile에서 bootsnap 관련 설정 자동 제거/비활성화

### 🐛 버그 수정
- Dockerfile bootsnap 프리컴파일 관련 다양한 엣지 케이스 처리

## [0.1.9] - 2025-01-17

### 🏗️ 기타 변경사항
- 홈페이지 URL을 TeamMilestone 조직으로 업데이트
- 저장소 이전에 따른 메타데이터 업데이트

## [0.1.0] - 2025-01-15

### 🎉 최초 릴리스
- `tayo init`: Rails 프로젝트 초기 설정 (Docker, Welcome 페이지)
- `tayo gh`: GitHub 저장소 및 Container Registry 설정
- `tayo cf`: Cloudflare DNS 설정
- OrbStack 자동 감지 및 실행
- 한국어 UI 지원