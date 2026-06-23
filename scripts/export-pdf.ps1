#Requires -Version 5.1
<#
.SYNOPSIS
  Mintlify MDX 문서를 Pandoc으로 단일 PDF로보냅니다.

.DESCRIPTION
  docs.json 네비게이션 순서대로 .mdx 파일을 읽어 Mintlify 전용 JSX를 제거·변환한 뒤
  하나의 Markdown으로 합치고 Pandoc(xelatex)으로 PDF를 생성합니다.

.PARAMETER OutputPdf
  생성할 PDF 파일 경로 (기본: build/AUDIGATE-manual.pdf)

.PARAMETER KeepIntermediate
  중간 산출물(combined.md)을 삭제하지 않고 보관합니다.

.PARAMETER MarkdownOnly
  PDF 생성 없이 build/combined.md만 생성합니다 (Pandoc 미설치 시 검증용).

.EXAMPLE
  .\scripts\export-pdf.ps1
  .\scripts\export-pdf.ps1 -OutputPdf ".\build\manual-ko.pdf" -KeepIntermediate
#>
[CmdletBinding()]
param(
    [string]$OutputPdf = "",
    [switch]$KeepIntermediate,
    [switch]$MarkdownOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# winget 설치 직후 열린 터미널에는 pandoc/xelatex PATH가 없을 수 있음
function Update-SessionPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path    = "$machinePath;$userPath"
}
Update-SessionPath

# ── 경로 설정 ──────────────────────────────────────────────────────────────
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ScriptsDir  = Join-Path $ProjectRoot "scripts"
$BuildDir    = Join-Path $ProjectRoot "build"
$DocsJson    = Join-Path $ProjectRoot "docs.json"
$MetadataFile = Join-Path $ScriptsDir "pandoc-metadata.yaml"

if ([string]::IsNullOrWhiteSpace($OutputPdf)) {
    $OutputPdf = Join-Path $BuildDir "AUDIGATE-manual.pdf"
}

$CombinedMarkdown = Join-Path $BuildDir "combined.md"

# 한글 PDF용 기본 폰트 (Windows: 맑은 고딕, 없으면 나눔고딕 시도)
$CjkMainFont = "Malgun Gothic"
$CjkFallbackFont = "NanumGothic"

# Mintlify 콜아웃 → PDF용 라벨 매핑
$CalloutLabels = @{
    "Info"    = "정보"
    "Note"    = "참고"
    "Warning" = "주의"
    "Tip"     = "팁"
    "Check"   = "확인"
}

# ── 사전 요구사항 검사 ─────────────────────────────────────────────────────
function Test-PandocPrerequisites {
    $missingTools = @()

    if (-not (Get-Command pandoc -ErrorAction SilentlyContinue)) {
        $missingTools += "pandoc"
    }

    $pdfEngine = $null
    foreach ($engine in @("xelatex", "lualatex", "pdflatex")) {
        if (Get-Command $engine -ErrorAction SilentlyContinue) {
            $pdfEngine = $engine
            break
        }
    }

    if (-not $pdfEngine) {
        $missingTools += "LaTeX (xelatex 또는 lualatex — MiKTeX / TeX Live)"
    }

    if ($missingTools.Count -gt 0) {
        Write-Error @"
필수 도구가 설치되어 있지 않습니다: $($missingTools -join ', ')

설치 방법:
  pandoc:  winget install JohnMacFarlane.Pandoc
           또는: choco install pandoc
  LaTeX:   winget install MiKTeX.MiKTeX
           또는 TeX Live 설치 후 PATH에 xelatex 추가

설치 후 터미널을 새로 열거나, 이 스크립트를 다시 실행하세요.
"@
    }

    return $pdfEngine
}

# ── docs.json에서 페이지 순서 읽기 ────────────────────────────────────────
function Get-NavigationPages {
    param([string]$DocsJsonPath)

    if (-not (Test-Path $DocsJsonPath)) {
        Write-Warning "docs.json을 찾을 수 없습니다. 폴더 순서로 MDX를 탐색합니다."
        return Get-FallbackPageOrder
    }

  try {
        $config = Get-Content -Path $DocsJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Warning "docs.json 파싱 실패: $($_.Exception.Message). 폴더 순서로 대체합니다."
        return Get-FallbackPageOrder
    }

    $orderedPages = [System.Collections.Generic.List[object]]::new()

    $navPages = $config.navigation.pages
    if (-not $navPages) {
        return Get-FallbackPageOrder
    }

    foreach ($group in $navPages) {
        $groupName = $group.group
        $pageList  = $group.pages

        if (-not $pageList) { continue }

        foreach ($page in $pageList) {
            if ($page -is [string]) {
                $orderedPages.Add([PSCustomObject]@{
                    Group = $groupName
                    Path  = $page
                })
            }
            elseif ($page.PSObject.Properties.Name -contains "pages") {
                # 중첩 그룹 (현재 프로젝트에는 없지만 확장 대비)
                foreach ($nested in $page.pages) {
                    $orderedPages.Add([PSCustomObject]@{
                        Group = if ($page.group) { $page.group } else { $groupName }
                        Path  = $nested
                    })
                }
            }
        }
    }

    if ($orderedPages.Count -eq 0) {
        return Get-FallbackPageOrder
    }

    return $orderedPages
}

# docs.json 없을 때 논리적 폴더 순서
function Get-FallbackPageOrder {
    $fallbackOrder = @(
        "index", "quickstart",
        "guides/installation", "guides/java-agent-installation", "guides/client-installation",
        "guides/basic-usage", "guides/dashboard", "guides/reports",
        "admin/overview", "admin/user-management", "admin/settings",
        "troubleshooting/faq", "troubleshooting/common-issues"
    )

    return $fallbackOrder | ForEach-Object {
        [PSCustomObject]@{ Group = ""; Path = $_ }
    }
}

# 페이지 경로 → 실제 .mdx 파일 경로
function Resolve-MdxFilePath {
    param(
        [string]$PagePath,
        [string]$Root
    )

    $normalized = $PagePath -replace '\\', '/'
    $candidates = @(
        (Join-Path $Root "$normalized.mdx"),
        (Join-Path $Root "$normalized\index.mdx")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

# ── MDX → Markdown 변환 ───────────────────────────────────────────────────
function Convert-MdxToMarkdown {
    param(
        [string]$RawContent,
        [string]$SourceFilePath,
        [string]$ProjectRootPath
    )

    $text = $RawContent

    # 1) YAML frontmatter 제거 (title은 호출부에서 별도 추출)
    $text = [regex]::Replace($text, '(?s)\A---\r?\n.*?\r?\n---\r?\n?', '')

    # 2) import 문 제거
    $text = [regex]::Replace($text, '(?m)^\s*import\s+.+$', '')

    # 3) Accordion → 소제목
    $text = [regex]::Replace($text, '<Accordion\s+title="([^"]+)"[^>]*>', {
        param($m)
        "### $($m.Groups[1].Value)`n`n"
    })
    $text = [regex]::Replace($text, "<Accordion\s+title='([^']+)'[^>]*>", {
        param($m)
        "### $($m.Groups[1].Value)`n`n"
    })
    $text = $text -replace '</Accordion>', ''
    $text = $text -replace '<AccordionGroup[^>]*>', ''
    $text = $text -replace '</AccordionGroup>', ''

    # 4) Step → 소제목 (Steps 블록 내 순서는 제목으로 구분)
    $text = [regex]::Replace($text, '<Step\s+title="([^"]+)"[^>]*>', {
        param($m)
        "### $($m.Groups[1].Value)`n`n"
    })
    $text = [regex]::Replace($text, "<Step\s+title='([^']+)'[^>]*>", {
        param($m)
        "### $($m.Groups[1].Value)`n`n"
    })
    $text = $text -replace '</Step>', ''
    $text = $text -replace '<Steps[^>]*>', ''
    $text = $text -replace '</Steps>', ''

    # 5) Card → 소제목 + 본문 (href는 참고 링크로 표시)
    $text = [regex]::Replace($text, '<Card\s+title="([^"]+)"[^>]*href="([^"]+)"[^>]*>', {
        param($m)
        "### $($m.Groups[1].Value)`n`n*(관련 문서: $($m.Groups[2].Value))*`n`n"
    })
    $text = [regex]::Replace($text, '<Card\s+title="([^"]+)"[^>]*>', {
        param($m)
        "### $($m.Groups[1].Value)`n`n"
    })
    $text = [regex]::Replace($text, "<Card\s+title='([^']+)'[^>]*href='([^']+)'[^>]*>", {
        param($m)
        "### $($m.Groups[1].Value)`n`n*(관련 문서: $($m.Groups[2].Value))*`n`n"
    })
    $text = [regex]::Replace($text, "<Card\s+title='([^']+)'[^>]*>", {
        param($m)
        "### $($m.Groups[1].Value)`n`n"
    })
    $text = $text -replace '</Card>', ''
    $text = $text -replace '<CardGroup[^>]*>', ''
    $text = $text -replace '</CardGroup>', ''

    # 6) Frame 래퍼 제거
    $text = $text -replace '<Frame[^>]*>', ''
    $text = $text -replace '</Frame>', ''

    # 7) 콜아웃 컴포넌트 → 인용 블록
    foreach ($component in $CalloutLabels.Keys) {
        $label = $CalloutLabels[$component]
        $calloutPrefix = "> **[$label]**`n>`n"
        $text = [regex]::Replace($text, "<$component[^>]*>", $calloutPrefix)
        $text = $text -replace "</$component>", ''
    }

    # 8) 남은 JSX 태그 제거 (자기닫힘 포함)
    $text = [regex]::Replace($text, '<[A-Za-z][A-Za-z0-9]*\s[^>]*/>', '')
    $text = [regex]::Replace($text, '<[A-Za-z][A-Za-z0-9]*[^>]*>', '')
    $text = [regex]::Replace($text, '</[A-Za-z][A-Za-z0-9]*>', '')

    # 9) JSX 속성 잔여물 정리 (cols={2} 등)
    $text = [regex]::Replace($text, '\b\w+\s*=\s*\{[^}]*\}', '')

    # 10) 이미지 경로 보정 (/images/... → 프로젝트 루트 기준)
    $sourceDir = Split-Path -Parent $SourceFilePath
    $text = [regex]::Replace($text, '!\[([^\]]*)\]\((/[^)]+)\)', {
        param($match)
        $altText = $match.Groups[1].Value
        $webPath = $match.Groups[2].Value.TrimStart('/')
        $absoluteImage = Join-Path $ProjectRootPath ($webPath -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (Test-Path $absoluteImage) {
            # Pandoc에 절대 경로 전달 (공백 대비)
            $escaped = $absoluteImage -replace '\\', '/'
            return "![$altText]($escaped)"
        }
        return "![$altText]($webPath)"
    })

    # 11) Mintlify 내부 링크 [/path](/path) → 일반 텍스트 경로
    $text = [regex]::Replace($text, '\[([^\]]+)\]\((/[^)]+)\)', '$1 ($2)')

    # 12) 연속 빈 줄 정리
    $text = [regex]::Replace($text, '(\r?\n){3,}', "`n`n")
    $text = $text.Trim()

    return $text
}

function Get-FrontmatterTitle {
    param([string]$RawContent)

    if ($RawContent -match '(?m)^title:\s*["'']([^"'']+)["'']') {
        return $Matches[1]
    }
    if ($RawContent -match "(?m)^title:\s*(\S+)") {
        return $Matches[1]
    }
    return $null
}

# ── 모든 페이지 합치기 ─────────────────────────────────────────────────────
function Build-CombinedMarkdown {
    param(
        [System.Collections.Generic.List[object]]$Pages,
        [string]$ProjectRootPath,
        [string]$OutputPath
    )

    $sb = [System.Text.StringBuilder]::new()
    $currentGroup = $null
    $processedCount = 0
    $skippedPages = [System.Collections.Generic.List[string]]::new()

    foreach ($entry in $Pages) {
        $pagePath = $entry.Path
        $groupName = $entry.Group

        $mdxFile = Resolve-MdxFilePath -PagePath $pagePath -Root $ProjectRootPath
        if (-not $mdxFile) {
            $skippedPages.Add($pagePath)
            Write-Warning "MDX 파일 없음, 건너뜀: $pagePath"
            continue
        }

        # 그룹 구분선 (네비게이션 그룹 변경 시)
        if ($groupName -and $groupName -ne $currentGroup) {
            $currentGroup = $groupName
            [void]$sb.AppendLine()
            [void]$sb.AppendLine("# $groupName")
            [void]$sb.AppendLine()
        }

        $raw = Get-Content -Path $mdxFile -Raw -Encoding UTF8
        $pageTitle = Get-FrontmatterTitle -RawContent $raw
        if (-not $pageTitle) {
            $pageTitle = Split-Path -Leaf $mdxFile -Base
        }

        $body = Convert-MdxToMarkdown -RawContent $raw -SourceFilePath $mdxFile -ProjectRootPath $ProjectRootPath

        [void]$sb.AppendLine()
        [void]$sb.AppendLine("## $pageTitle")
        [void]$sb.AppendLine()
        [void]$sb.AppendLine($body)
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('\newpage')
        [void]$sb.AppendLine()

        $processedCount++
    }

    if ($processedCount -eq 0) {
        throw "변환할 MDX 페이지가 없습니다."
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($OutputPath, $sb.ToString(), $utf8NoBom)

    if ($skippedPages.Count -gt 0) {
        Write-Warning "건너뛴 페이지: $($skippedPages -join ', ')"
    }

    Write-Host "합친 Markdown: $OutputPath ($processedCount 페이지)" -ForegroundColor Green
}

# ── Pandoc PDF 생성 ────────────────────────────────────────────────────────
function Invoke-PandocPdf {
    param(
        [string]$InputMarkdown,
        [string]$OutputPdfPath,
        [string]$PdfEngine,
        [string]$MetadataPath
    )

    if (-not (Test-Path $MetadataPath)) {
        Write-Warning "메타데이터 파일 없음: $MetadataPath (기본값 사용)"
    }

    $pandocArgs = @(
        $InputMarkdown,
        "-o", $OutputPdfPath,
        "--from", "markdown",
        "--pdf-engine=$PdfEngine",
        "--toc",
        "--toc-depth=3",
        "--number-sections",
        "--metadata-file=$MetadataPath",
        "-V", "CJKmainfont=$CjkMainFont",
        "-V", "geometry:margin=2.5cm",
        "-V", "fontsize=11pt",
        "-V", "documentclass=article",
        "--highlight-style=tango"
    )

    Write-Host "Pandoc 실행 중 (엔진: $PdfEngine)..." -ForegroundColor Cyan
    Write-Host "  pandoc $($pandocArgs -join ' ')" -ForegroundColor DarkGray

    # pandoc 경고가 stderr로 출력되면 Stop 모드에서 오류로 처리될 수 있음
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & pandoc @pandocArgs
        if ($LASTEXITCODE -ne 0) {
            # 맑은 고딕 실패 시 대체 폰트로 재시도
            if ($PdfEngine -eq "xelatex") {
                Write-Warning "CJKmainfont=$CjkMainFont 실패 가능 — $CjkFallbackFont 로 재시도합니다."
                $pandocArgs = $pandocArgs | ForEach-Object {
                    if ($_ -eq $CjkMainFont) { $CjkFallbackFont } else { $_ }
                }
                # -V CJKmainfont=... 쌍 수정
                for ($i = 0; $i -lt $pandocArgs.Count; $i++) {
                    if ($pandocArgs[$i] -eq "-V" -and $pandocArgs[$i + 1] -eq "CJKmainfont=$CjkMainFont") {
                        $pandocArgs[$i + 1] = "CJKmainfont=$CjkFallbackFont"
                    }
                }
                & pandoc @pandocArgs
            }
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Pandoc PDF 생성 실패 (종료 코드: $LASTEXITCODE). LaTeX 로그를 확인하세요."
    }

    if (-not (Test-Path $OutputPdfPath)) {
        throw "PDF 파일이 생성되지 않았습니다: $OutputPdfPath"
    }

    $fileSizeKb = [math]::Round((Get-Item $OutputPdfPath).Length / 1KB, 1)
    Write-Host "PDF 생성 완료: $OutputPdfPath ($fileSizeKb KB)" -ForegroundColor Green
}

# ── 메인 실행 ──────────────────────────────────────────────────────────────
function Main {
    Write-Host "=== AUDIGATE 매뉴얼 PDF보내기 ===" -ForegroundColor Cyan
    Write-Host "프로젝트: $ProjectRoot"

    if (-not (Test-Path $BuildDir)) {
        New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
    }

    $pages = Get-NavigationPages -DocsJsonPath $DocsJson
    Write-Host "네비게이션 페이지: $($pages.Count)개" -ForegroundColor DarkGray

    Build-CombinedMarkdown -Pages $pages -ProjectRootPath $ProjectRoot -OutputPath $CombinedMarkdown

    if ($MarkdownOnly) {
        Write-Host "MarkdownOnly 모드 — PDF 생성을 건너뜁니다." -ForegroundColor Yellow
        Write-Host "완료." -ForegroundColor Green
        return
    }

    $pdfEngine = Test-PandocPrerequisites
    Write-Host "PDF 엔진: $pdfEngine" -ForegroundColor DarkGray

    Invoke-PandocPdf -InputMarkdown $CombinedMarkdown -OutputPdfPath $OutputPdf -PdfEngine $pdfEngine -MetadataPath $MetadataFile

    Write-Host ""
    Write-Host "완료." -ForegroundColor Green
}

Main
