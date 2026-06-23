> Mintlify 제품 지식(컴포넌트, 설정, 작성 표준)은 `npx skills add https://mintlify.com/docs` 로 스킬을 설치하세요.

# Audigate Manual — 문서 작성 가이드

## 프로젝트 개요

- Audigate 제품 사용 메뉴얼 (한국어)
- [Mintlify](https://mintlify.com) 기반 MDX 문서 사이트
- 설정 파일: `docs.json`
- 페이지: `*.mdx` (YAML frontmatter 필수)

## 용어

| 용어 | 설명 |
| --- | --- |
| **Audigate** | 감사·컴플라이언스 플랫폼 제품명 |
| **업무** | 사용자에게 할당된 감사·검토 작업 단위 |
| **역할(Role)** | Viewer, Editor, Reviewer, Admin 등 권한 묶음 |
| **관리 콘솔** | 관리자 전용 설정 화면 |

## 작성 스타일

- 한국어로 작성, 존댓말(합니다체) 사용
- 독자는 제품 사용자·관리자 — 2인칭("~하세요")으로 안내
- UI 요소는 **굵게**: **설정**, **저장**
- 파일명·경로·명령어는 코드 형식: `docs.json`, `mint dev`
- 제목은 문장형 소문자 대신 명사형 사용 (예: "기본 사용법")

## 콘텐츠 범위

- 포함: 설치, 사용법, 관리자 설정, FAQ, 문제 해결
- 제외: 내부 개발 API, 미공개 기능, 고객사별 커스텀 상세

## 페이지 추가 시

1. 해당 폴더에 `.mdx` 파일 생성
2. `docs.json` navigation에 경로 등록
3. `mint validate`로 빌드 오류 확인
