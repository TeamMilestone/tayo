# tayo cf 명령어 리팩토링

**날짜**: 2025-11-29

## 변경 사항

### 문제점

1. **흐름이 어색함**: 도메인 입력을 먼저 받고 나서 Cloudflare Zone 목록을 보여주는 순서가 비직관적
2. **기존 레코드 확인 버그**: `check_existing_records`가 `domain_info`를 파라미터로 받지만 사용하지 않고, 항상 루트 도메인만 조회
3. **권한 안내 오류**: DNS 편집 권한만 있으면 읽기도 가능한데, 불필요하게 읽기 권한도 안내

### 해결

#### 새로운 흐름

```
기존:                          변경 후:
1. 도메인 입력                  1. 토큰 입력
2. 토큰 입력                    2. Zone 선택
3. Zone 선택                    3. 기존 레코드 목록 표시
4. 기존 레코드 확인 (버그)       4. 서비스 도메인 입력
5. DNS 레코드 설정              5. 홈서버 연결 정보 입력
6. deploy.yml 업데이트          6. DNS 레코드 생성/수정
7. Git 커밋                     7. deploy.yml 업데이트
                                8. Git 커밋
```

#### 주요 변경 내용

1. **`show_existing_records` 메서드 추가**
   - Zone 전체의 A/CNAME 레코드를 조회하여 표시
   - `get_all_dns_records` 헬퍼 메서드로 name 필터 없이 조회

2. **`get_domain_input` 수정**
   - Zone 정보를 파라미터로 받아서 활용
   - 서브도메인 사용 여부를 먼저 질문 후 입력받음

3. **`get_server_info` 메서드 분리**
   - 기존 `setup_dns_record`에서 서버 정보 입력 로직 분리
   - "홈서버 연결 정보" 단계로 명명

4. **`setup_dns_record` 단순화**
   - 인스턴스 변수 대신 파라미터로 데이터 전달
   - `determine_final_domain` 로직 제거 (사용자가 직접 선택)

5. **권한 안내 수정**
   - "영역 → DNS → 읽기" 제거
   - "영역 → DNS → 편집"만 안내

## 파일 변경

- `lib/tayo/commands/cf.rb`: 143 insertions, 113 deletions
