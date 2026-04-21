# PSSnips — Repository factory helper

function script:New-SnipRepository {
    [CmdletBinding()]
    [OutputType([SnipRepositoryBase])]
    param(
        [ValidateSet('Json')]
        [string]$Type = 'Json',
        [string]$Path = $script:Home
    )
    switch ($Type) {
        'Json' { return [JsonSnipRepository]::new($Path) }
    }
}
