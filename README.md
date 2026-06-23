# Audigate Manual

Audigate 제품 사용 메뉴얼 — [Mintlify](https://mintlify.com) 기반 문서 사이트입니다.

## 로컬 개발

### 사전 요구사항

- Node.js 20.17.0 이상
- Mintlify CLI

### CLI 설치

```bash
npm i -g mint
```

### 로컬 미리보기

프로젝트 루트(`docs.json`이 있는 위치)에서 실행:

```bash
mint dev
```

브라우저에서 `http://localhost:3000` 으로 접속합니다.

### 빌드 검증

```bash
mint validate
```

## 프로젝트 구조

```
AudigateManual/
├── docs.json              # 사이트 설정 및 네비게이션
├── index.mdx              # 홈 (소개)
├── quickstart.mdx         # 빠른 시작
├── guides/                # 사용자 가이드
├── admin/                 # 관리자 가이드
├── troubleshooting/       # FAQ & 문제 해결
├── logo/                  # 로고 (light/dark)
└── favicon.svg
```

## 페이지 추가 방법

1. `guides/` 등 적절한 폴더에 `.mdx` 파일 생성
2. `docs.json`의 `navigation.pages`에 경로 추가 (확장자 제외, 예: `guides/new-page`)
3. `mint dev`로 미리보기 확인

## 배포

[Mintlify 대시보드](https://dashboard.mintlify.com)에서 GitHub 저장소를 연결하면 `main` 브랜치 push 시 자동 배포됩니다.

## AI 도구 연동 (선택)

```bash
npx skills add https://mintlify.com/docs
```

Mintlify 문서 작성 스킬을 Cursor 등 AI 도구에 추가할 수 있습니다.
