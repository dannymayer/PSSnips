# PSSnips — JSON-backed snippet repository implementation

class JsonSnipRepository : SnipRepositoryBase {
    hidden [string]    $BasePath
    hidden [string]    $IdxFile
    hidden [string]    $CfgFile
    hidden [string]    $SnipDir
    hidden [hashtable] $_idxCache  = $null
    hidden [bool]      $_idxDirty  = $true
    hidden [hashtable] $_cfgCache  = $null
    hidden [bool]      $_cfgDirty  = $true

    JsonSnipRepository([string]$basePath) {
        $this.BasePath = $basePath
        $this.IdxFile  = Join-Path $basePath 'index.json'
        $this.CfgFile  = Join-Path $basePath 'config.json'
        $this.SnipDir  = Join-Path $basePath 'snippets'
    }

    [hashtable] GetIndex() {
        return & $script:_LoadIdxDelegate
    }

    [void] SaveIndex([hashtable]$idx) {
        & $script:_SaveIdxDelegate $idx
    }

    [hashtable] GetConfig() {
        return & $script:_LoadCfgDelegate
    }

    [void] SaveConfig([hashtable]$cfg, [string]$scope) {
        & $script:_SaveCfgDelegate $cfg $scope
    }

    [string] GetSnipContent([string]$name) {
        $f = $this.FindSnipFile($name)
        if (-not $f) { return $null }
        return Get-Content $f -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    }

    [void] SaveSnipContent([string]$name, [string]$content, [string]$ext) {
        $path = Join-Path $this.SnipDir "$name.$ext"
        Set-Content -Path $path -Value $content -Encoding UTF8 -Force
    }

    [void] DeleteSnipContent([string]$name, [string]$ext) {
        $path = Join-Path $this.SnipDir "$name.$ext"
        if (Test-Path $path) { Remove-Item $path -Force }
    }

    [string] FindSnipFile([string]$name) {
        $hits = @(Get-ChildItem $this.SnipDir -Filter "$name.*" -File -ErrorAction SilentlyContinue)
        if ($hits.Count -gt 0) { return $hits[0].FullName }
        return $null
    }

    [void] InvalidateCache() {
        $this._idxDirty = $true
        $this._cfgDirty = $true
        & $script:_InvalidateDelegate
    }
}
