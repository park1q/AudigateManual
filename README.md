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

## PDF보내기

Mintlify MDX 문서를 단일 PDF로내려면 [Pandoc](https://pandoc.org)과 LaTeX 엔진이 필요합니다.

### 사전 요구사항

| 도구 | 용도 | 설치 (Windows) |
| --- | --- | --- |
| **Pandoc** | MDX → PDF 변환 | `winget install JohnMacFarlane.Pandoc` 또는 `choco install pandoc` |
| **MiKTeX** 또는 **TeX Live** | PDF 생성 (`xelatex`) | `winget install MiKTeX.MiKTeX` |

한글 렌더링은 `xelatex` + 맑은 고딕(`Malgun Gothic`)을 사용합니다. 설치 후 **새 터미널**을 열어 PATH가 반영됐는지 확인하세요.

```powershell
pandoc --version
xelatex --version
```

### 실행

프로젝트 루트에서:

```powershell
.\scripts\export-pdf.ps1
```

출력 파일: `build/AUDIGATE-manual.pdf`  
중간 Markdown: `build/combined.md` (디버깅·검토용)

옵션 예시:

```powershell
.\scripts\export-pdf.ps1 -OutputPdf ".\build\manual-ko.pdf"
```

Pandoc 없이 변환 결과만 확인:

```powershell
.\scripts\export-pdf.ps1 -MarkdownOnly
```

### 제한 사항

- Mintlify 전용 UI(`<Card>`, `<Steps>`, `<Accordion>` 등)는 PDF에서 **텍스트·소제목**으로만 변환됩니다.
- 카드 링크(`href`)는 참고용 경로 텍스트로 표시되며 클릭 불가입니다.
- SVG 로고·일부 이미지는 LaTeX에서 렌더링되지 않을 수 있습니다.
- 웹 전용 인터랙션(탭, 접이식 UI)은 지원되지 않습니다.

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
├── scripts/               # PDF보내기 스크립트
│   ├── export-pdf.ps1
│   └── pandoc-metadata.yaml
├── build/                 # PDF보내기 산출물 (gitignore)
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
