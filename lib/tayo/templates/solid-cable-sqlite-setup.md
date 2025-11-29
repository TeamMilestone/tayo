# Solid Cable + SQLite 최적화 설정

> 이 문서는 `tayo sqlite` 명령어로 자동 생성되었습니다.

## 개요

이 프로젝트는 Redis 없이 SQLite만으로 Action Cable 실시간 기능을 구현합니다.
Rails 8에서 도입된 Solid Cable을 사용하여 WebSocket 브로드캐스트를 처리합니다.

## 왜 Solid Cable인가?

### Redis vs Solid Cable

| 항목 | Redis | Solid Cable |
|------|-------|-------------|
| 의존성 | Redis 서버 필요 | DB만 사용 |
| 방식 | Pub/Sub (푸시) | Polling (폴링) |
| 지연시간 | ~1ms | ~25ms (설정값) |
| 운영 복잡도 | Redis 관리 필요 | 단순 |

### 체감 성능

- **25ms 폴링**: 사용자가 지연을 체감하기 어려움 (200ms 이하는 "즉각적"으로 느껴짐)
- **RTT 비교**: Redis ~80ms vs Solid Cable ~85ms (전체 왕복 시간 기준, 거의 동일)

## 적용된 설정

### 1. 데이터베이스 분리 (database.yml)

```yaml
production:
  primary:
    database: storage/production.sqlite3
  cable:
    database: storage/production_cable.sqlite3  # 별도 DB
```

**이유**: Cable 폴링이 메인 DB의 쓰기 작업과 락 경합하지 않도록 분리

### 2. Cable 설정 (cable.yml)

```yaml
development:
  adapter: async  # 단일 프로세스, 콘솔 디버깅 용이

production:
  adapter: solid_cable
  polling_interval: 0.025.seconds  # 25ms
  message_retention: 1.hour
```

**폴링 간격 선택 기준**:
- 100ms: 기본값, 대부분 충분
- 25ms: 채팅/실시간 앱에 적합
- 10ms: Redis 수준, 부하 증가

### 3. SQLite WAL 모드 최적화 (initializer)

```ruby
# config/initializers/solid_cable_sqlite.rb
PRAGMA journal_mode=WAL      # 읽기/쓰기 동시 처리
PRAGMA synchronous=NORMAL    # 쓰기 성능 향상
PRAGMA cache_size=4000       # 캐시 증가
```

**WAL 모드 장점**:
- 읽기(폴링)와 쓰기(브로드캐스트)가 동시에 가능
- Solid Cable의 폴링 패턴에 최적화

## 성능 가이드

### 적정 사용 범위

| 동시 접속 | 메시지/초 | 예상 지연 |
|----------|----------|----------|
| ~50명 | ~10 | 거의 없음 |
| ~100명 | ~20 | ~50ms |
| ~500명 | ~100 | 검토 필요 |

### 스케일 아웃이 필요한 경우

- 초당 200개 이상 메시지
- 1000명 이상 동시 접속
- → Redis 또는 PostgreSQL NOTIFY 고려

## 참고 자료

- [Solid Cable GitHub](https://github.com/rails/solid_cable)
- [SQLite WAL Mode](https://sqlite.org/wal.html)
- [Rails 8 Release Notes](https://rubyonrails.org/2024/11/7/rails-8-no-paas-required)
